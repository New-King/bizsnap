import { Hono } from 'hono';
import { z } from 'zod';
import { markCardsConfirmed } from '../db/threads.js';
import { parse, readJson } from '../http.js';
import { confirmCards, type WrittenCard } from '../services/confirm.js';
import { streamFailureNote, streamInsight } from '../services/insight.js';
import { sseResponse } from '../sse.js';
import type { CardDraft } from '../types.js';

export const confirmRoutes = new Hono();

const KIND_LABEL: Record<WrittenCard['kind'], string> = {
  create_contact: '创建联系人',
  update_contact: '更新联系人',
  create_meeting: '创建会议',
};

/**
 * 没有洞察可写时的兜底回应：确认这一步必须有文字。
 * 卡片上只有类型，为什么没成、几张成了，只能由这句话交代。
 */
function statusNote(written: WrittenCard[]): string {
  const failed = written.filter((item) => !item.ok);
  if (!failed.length) return '已经按卡片写好了。';

  const detail = failed
    .map((item) => {
      const who = item.contactName ? `（${item.contactName}）` : '';
      return `${KIND_LABEL[item.kind] ?? item.kind}${who}：${item.error ?? '写入失败'}`;
    })
    .join('；');

  const okCount = written.length - failed.length;
  return okCount
    ? `有 ${okCount} 张已经写进去了；剩下没成的是——${detail}。改一句再让我重出卡片。`
    : `这几张都没能写进去——${detail}。改一句再让我重出卡片。`;
}

const cardSchema = z.object({
  id: z.string(),
  kind: z.enum(['create_contact', 'update_contact', 'create_meeting']),
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

    const failures = result.written
      .filter((item) => !item.ok)
      .map((item) => ({
        label: KIND_LABEL[item.kind] ?? item.kind,
        who: item.contactName ?? '',
        reason: item.error ?? '写入失败',
      }));
    const okCount = result.written.length - failures.length;

    if (!result.insightSource || signal.aborted) {
      // 连主联系人都没定位到（比如更新卡的目标不存在）：仍然让模型说这段，
      // 模板文案只在模型也调不出来时兜底
      const note = signal.aborted
        ? ''
        : await streamFailureNote(failures, okCount, (delta) => send({ type: 'text', delta }));
      if (!signal.aborted && !note.trim()) send({ type: 'text', delta: statusNote(result.written) });
      send({ type: 'done', insight: '', contactName: result.contactName });
      return;
    }

    // 洞察逐字流出，不阻塞客户端的系统写入；有没写成的卡时第一句先交代它
    const insight = await streamInsight(
      result.insightSource,
      (delta) => send({ type: 'text', delta }),
      failures,
    );
    if (!signal.aborted) {
      // 模型也生成不出来时才退回模板：确认完不能没有任何回音
      if (!insight.trim()) send({ type: 'text', delta: statusNote(result.written) });
      send({ type: 'done', insight, contactName: result.contactName });
    }
  });
});
