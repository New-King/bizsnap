import { Hono } from 'hono';
import { z } from 'zod';
import { markCardsConfirmed } from '../db/threads.js';
import { parse, readJson } from '../http.js';
import { confirmCards } from '../services/confirm.js';
import { streamInsight } from '../services/insight.js';
import { sseResponse } from '../sse.js';
import type { CardDraft } from '../types.js';

export const confirmRoutes = new Hono();

const cardSchema = z.object({
  id: z.string(),
  kind: z.enum(['create_contact', 'update_contact', 'create_meeting']),
  reason: z.string().optional(),
  payload: z.record(z.string(), z.unknown()),
});

const confirmSchema = z.object({ cards: z.array(cardSchema).min(1) });

confirmRoutes.post('/threads/:id/confirm', async (c) => {
  const threadId = c.req.param('id');
  const body = parse(confirmSchema, await readJson(c));
  const cards = body.cards as unknown as CardDraft[];
  const signal = c.req.raw.signal;

  return sseResponse(signal, async (send) => {
    // 1. 落库（事务在 confirmCards 里），2. 标记卡片已确认
    const result = await confirmCards(threadId, cards);
    await markCardsConfirmed(
      threadId,
      result.written.filter((item) => item.ok).map((item) => item.cardId),
    );

    // 事务提交后才告诉客户端：此时可以开始写系统通讯录 / 日历
    send({ type: 'written', written: result.written, contactName: result.contactName });

    if (!result.insightSource || signal.aborted) {
      send({ type: 'done', insight: '', contactName: result.contactName });
      return;
    }

    // 洞察逐字流出，不阻塞客户端的系统写入
    const insight = await streamInsight(result.insightSource, (delta) => send({ type: 'text', delta }));
    if (!signal.aborted) {
      send({ type: 'done', insight, contactName: result.contactName });
    }
  });
});
