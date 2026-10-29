import { Router } from 'express';
import { RequestContext } from '@mastra/core/request-context';
import { z } from 'zod';
import { RESOURCE_ID } from '../config.js';
import { newId } from '../db/contacts.js';
import {
  deleteMessage,
  getThread,
  insertMessage,
  listConfirmedCardIds,
  listMessages,
  updateThread,
} from '../db/threads.js';
import { bizAgent } from '../mastra/agent.js';
import { buildPrompt } from '../mastra/prompt.js';
import type { CardDraft } from '../types.js';

export const messagesRouter = Router();

const DRAFT_TOOLS = new Set(['create_contact', 'update_contact', 'create_meeting']);

/** 客户端默认压成 JPEG，但截图来源可能是 PNG，按文件头判断 */
function detectMediaType(base64: string): string {
  if (base64.startsWith('/9j/')) return 'image/jpeg';
  if (base64.startsWith('iVBORw0KGgo')) return 'image/png';
  if (base64.startsWith('UklGR')) return 'image/webp';
  return 'image/jpeg';
}

const snapshotSchema = z.array(
  z.object({
    name: z.string(),
    company: z.string().optional(),
    position: z.string().optional(),
    phones: z.array(z.string()).optional(),
  }),
);

const sendSchema = z.object({
  text: z.string().optional(),
  imageBase64: z.string().optional(),
  contactsSnapshot: snapshotSchema.max(200).optional(),
});

type ToolResultChunkLike = {
  payload: { toolCallId: string; toolName: string; result: unknown };
};

/** 从工具执行结果里捞回卡片草案：卡片不由模型直接输出，工具返回什么就是什么 */
function collectCards(result: {
  toolResults?: ToolResultChunkLike[];
  steps?: { toolResults?: ToolResultChunkLike[] }[];
}): CardDraft[] {
  const seen = new Map<string, ToolResultChunkLike>();
  for (const chunk of result.toolResults ?? []) seen.set(chunk.payload.toolCallId, chunk);
  for (const step of result.steps ?? []) {
    for (const chunk of step.toolResults ?? []) seen.set(chunk.payload.toolCallId, chunk);
  }

  const cards: CardDraft[] = [];
  for (const chunk of seen.values()) {
    if (!DRAFT_TOOLS.has(chunk.payload.toolName)) continue;
    const payload = chunk.payload.result as { card?: CardDraft } | null;
    if (payload?.card) cards.push(payload.card);
  }
  return cards;
}

messagesRouter.get('/threads/:id/messages', async (req, res, next) => {
  try {
    const messages = await listMessages(req.params.id);
    const confirmed = new Set(await listConfirmedCardIds(req.params.id));
    res.json(
      messages.map((message) => ({
        ...message,
        cards: message.cards?.map((card) => ({ ...card, confirmed: confirmed.has(card.id) })),
      })),
    );
  } catch (error) {
    next(error);
  }
});

messagesRouter.post('/threads/:id/messages', async (req, res, next) => {
  try {
    const threadId = req.params.id;
    const thread = await getThread(threadId);
    if (!thread) {
      res.status(404).json({ error: '会话不存在' });
      return;
    }

    const body = sendSchema.parse(req.body ?? {});
    const text = body.text?.trim() ?? '';
    const imageBase64 = body.imageBase64?.trim() || undefined;
    if (!text && !imageBase64) {
      res.status(400).json({ error: '请发一句话或一张截图' });
      return;
    }

    const userMessageId = newId();
    await insertMessage(threadId, { id: userMessageId, role: 'user', text, imageBase64 });
    if (!thread.title && text) {
      await updateThread(threadId, { title: text.slice(0, 16) });
    }

    const content: (
      | { type: 'text'; text: string }
      | { type: 'image'; image: Uint8Array; mediaType: string }
    )[] = [];
    if (imageBase64) {
      content.push({
        type: 'image',
        image: Buffer.from(imageBase64, 'base64'),
        mediaType: detectMediaType(imageBase64),
      });
    }
    content.push({ type: 'text', text: text || '请读这张截图里的商务信息。' });

    const requestContext = new RequestContext();
    requestContext.set('contactsSnapshot', body.contactsSnapshot ?? []);

    let result;
    try {
      result = await bizAgent.generate(
        [{ role: 'user', content }],
        {
          instructions: buildPrompt(),
          memory: { thread: threadId, resource: RESOURCE_ID },
          requestContext,
          // 允许「查人 → 查历史 → 出卡片」多步推理
          maxSteps: 5,
        },
      );
    } catch (error) {
      // 失败就把这轮用户消息撤掉：客户端重试时不会再叠一条
      await deleteMessage(userMessageId);
      throw error;
    }

    const cards = collectCards(result);
    const replyText = (result.text ?? '').trim() || (cards.length ? '已生成卡片，请确认。' : '没有识别到可记录的信息。');

    const message = await insertMessage(threadId, {
      id: newId(),
      role: 'assistant',
      text: replyText,
      cards: cards.length ? cards : undefined,
    });

    // 纯截图进来的会话没有文字标题，用卡片上的人补一个
    if (!thread.title) {
      const owner = cards.find((card) => card.kind !== 'create_meeting')?.payload;
      const name = owner && 'name' in owner ? owner.name : owner && 'targetName' in owner ? owner.targetName : '';
      if (name) await updateThread(threadId, { title: name });
    }

    res.json({ message });
  } catch (error) {
    next(error);
  }
});
