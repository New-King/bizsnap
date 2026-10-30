import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { normalizeName, searchByEmbedding, searchByKeyword } from '../../db/contacts.js';
import { embedText } from '../../services/embedding.js';
import { currentValues, renderTimeline } from '../../services/attributes.js';
import type { ContactCandidate, ContactRecord, DeviceContactSnapshot } from '../../types.js';

function isInDevice(contact: ContactRecord, snapshot: DeviceContactSnapshot[]): boolean {
  if (!snapshot.length) return false;
  const targetName = normalizeName(contact.name);
  const targetPhone = contact.phone.replace(/\D/g, '');
  return snapshot.some((item) => {
    if (normalizeName(item.name) === targetName) return true;
    if (!targetPhone) return false;
    return (item.phones ?? []).some((phone) => phone.replace(/\D/g, '').endsWith(targetPhone.slice(-7)));
  });
}

function toCandidate(
  contact: ContactRecord,
  matchedIn: ContactCandidate['matchedIn'],
  snapshot: DeviceContactSnapshot[],
): ContactCandidate {
  return {
    id: contact.id,
    name: contact.name,
    now: currentValues(contact),
    timeline: renderTimeline(contact),
    matchedIn,
    inDevice: isInDevice(contact, snapshot),
  };
}

export const searchContact = createTool({
  id: 'search_contact',
  description:
    '按姓名、电话、公司或一句模糊描述查已记住的人。凡涉及具体的人，先调用它，不要凭印象回答。返回候选人的当前状态与时间线。它描述的是这个人现在是什么样；要找往事用 search_interactions。',
  inputSchema: z.object({
    query: z.string().min(1).describe('姓名、电话、公司，或「上次做跨境支付那个」这类描述'),
    when: z
      .enum(['now', 'any'])
      .optional()
      .describe("'now' 只看当前状态（问「现在谁负责」时用）；'any' 含历史，默认 any"),
  }),
  execute: async ({ query, when }, context) => {
    const snapshot = (context?.requestContext?.get('contactsSnapshot') as DeviceContactSnapshot[] | undefined) ?? [];
    const mode = when ?? 'any';

    const hits = await searchByKeyword(query);
    const merged = new Map<string, { contact: ContactRecord; matchedIn: ContactCandidate['matchedIn'] }>();
    for (const hit of hits) {
      merged.set(hit.contact.id, { contact: hit.contact, matchedIn: hit.matchedIn });
    }

    // 关键词命中不足 3 个时，用向量找补「做建筑设计的那个」这类换说法的描述。
    // 向量只覆盖当前值，历史值靠 search_history 的 LIKE 和 search_interactions
    if (merged.size < 3) {
      try {
        const vector = await embedText(query);
        const semantic = await searchByEmbedding(vector, 5);
        for (const item of semantic) {
          if (!merged.has(item.contact.id)) {
            merged.set(item.contact.id, { contact: item.contact, matchedIn: 'semantic' });
          }
        }
      } catch (error) {
        console.warn('[bizsnap] 语义检索不可用：', (error as Error).message);
      }
    }

    let candidates = [...merged.values()];
    if (mode === 'now') {
      candidates = candidates.filter((item) => item.matchedIn !== 'history');
    }

    const list = candidates
      .slice(0, 10)
      .map((item) => toCandidate(item.contact, item.matchedIn, snapshot));

    return {
      query,
      when: mode,
      total: list.length,
      inDevice: list.some((item) => item.inDevice),
      candidates: list,
      note: list.length ? '' : '库里没有匹配的人，可能是新联系人。',
    };
  },
});
