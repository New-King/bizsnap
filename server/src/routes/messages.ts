import { RequestContext } from '@mastra/core/request-context';
import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
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
import { notFound, parse, readJson } from '../http.js';
import { bizAgent } from '../mastra/agent.js';
import { buildPrompt } from '../mastra/prompt.js';
import { generateTitle } from '../mastra/title.js';
import { sseResponse } from '../sse.js';
import type { CardDraft } from '../types.js';

export const messageRoutes = new Hono();

/** 只有这三个工具会产出卡片草案，其余工具结果不进消息 */
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

messageRoutes.get('/threads/:id/messages', async (c) => {
  const id = c.req.param('id');
  const messages = await listMessages(id);
  const confirmed = new Set(await listConfirmedCardIds(id));
  return c.json(
    messages.map((message) => ({
      ...message,
      cards: message.cards?.map((card) => ({ ...card, confirmed: confirmed.has(card.id) })),
    })),
  );
});

messageRoutes.post('/threads/:id/messages', async (c) => {
  const threadId = c.req.param('id');
  const thread = await getThread(threadId);
  if (!thread) throw notFound('会话不存在');

  const body = parse(sendSchema, await readJson(c));
  const text = body.text?.trim() ?? '';
  const imageBase64 = body.imageBase64?.trim() || undefined;
  if (!text && !imageBase64) {
    throw new HTTPException(400, { message: '请发一句话或一张截图' });
  }

  const userMessageId = newId();
  await insertMessage(threadId, { id: userMessageId, role: 'user', text, imageBase64 });

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

  const assistantId = newId();
  const signal = c.req.raw.signal;

  return sseResponse(signal, async (send) => {
    send({ type: 'start', threadId, messageId: assistantId });

    let reply = '';
    const cards: CardDraft[] = [];

    try {
      const stream = await bizAgent.stream(
        [{ role: 'user', content }],
        {
          instructions: buildPrompt(),
          memory: { thread: threadId, resource: RESOURCE_ID },
          requestContext,
          // 允许「查人 → 查历史 → 出卡片」多步推理
          maxSteps: 5,
        },
      );

      for await (const chunk of stream.fullStream) {
        if (signal.aborted) break;

        if (chunk.type === 'text-delta') {
          const delta = chunk.payload?.text ?? '';
          if (delta) {
            reply += delta;
            send({ type: 'text', delta });
          }
          continue;
        }

        // 草案不等整段文字结束：工具一返回就推给前端
        if (chunk.type === 'tool-result') {
          const payload = chunk.payload as { toolName?: string; result?: { draft?: CardDraft } };
          if (payload.toolName && DRAFT_TOOLS.has(payload.toolName) && payload.result?.draft) {
            cards.push(payload.result.draft);
            send({ type: 'card', card: payload.result.draft });
          }
        }
      }
    } catch (error) {
      // 这一轮没成功：撤掉用户消息，客户端重试时不会在库里叠出两条
      await deleteMessage(userMessageId);
      throw error;
    }

    if (signal.aborted) {
      // 客户端断开：撤掉本轮用户消息，不留半条记录
      await deleteMessage(userMessageId);
      return;
    }

    const replyText =
      reply.trim() || (cards.length ? '整理好了，看一眼对不对。' : '没有识别到可记录的信息。');

    // 模型只调了工具、没写字：把兜底文案当成一次正文补发。
    // 前端规定「先正文、后卡片」，缺了这条正文，卡片会一直压着不显示。
    if (!reply.trim()) send({ type: 'text', delta: replyText });

    const message = await insertMessage(threadId, {
      id: assistantId,
      role: 'assistant',
      text: replyText,
      cards: cards.length ? cards : undefined,
    });

    // 先发 done：卡片随它一起落位。标题要再调一次模型，别挡在它前面
    send({ type: 'done', message, title: thread.title || undefined });

    // 首轮补标题：done 之后再生成，单独一帧回给前端；失败不影响这一轮
    if (!thread.title.trim()) {
      const generated = await generateTitle(text, replyText).catch(() => '');
      if (generated) {
        await updateThread(threadId, { title: generated });
        send({ type: 'title', title: generated });
      }
    }
  });
});
