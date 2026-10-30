import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { searchInteractionsByKeywords } from '../../db/contacts.js';

/**
 * 把模型给的词再切成 2-gram 补充：中文没有空格，整词匹配容易漏。
 * 「跨境支付」→ 跨境 / 境支 / 支付，任一片段命中都算候选。
 */
function expandKeywords(keys: string[]): string[] {
  const set = new Set<string>();
  for (const key of keys) {
    const trimmed = key.trim();
    if (!trimmed) continue;
    set.add(trimmed);
    for (let i = 0; i + 2 <= trimmed.length; i += 1) {
      set.add(trimmed.slice(i, i + 2));
    }
  }
  return [...set];
}

export const searchInteractions = createTool({
  id: 'search_interactions',
  description:
    '按关键词搜历史事件记录：谁、什么时候、因为什么见过面、改过什么。search_contact 没找到人，或要凭一句模糊描述回忆往事（「上次做跨境支付那个」）时用。返回事件原文，由你判断是不是同一个人。',
  inputSchema: z.object({
    keywords: z
      .array(z.string())
      .min(1)
      .describe('从用户那句话里取出的实词，2~6 字一个，多给两三个，如「跨境支付」「外贸结算」'),
    limit: z.number().int().min(1).max(20).optional().describe('最多返回几条，默认 8'),
  }),
  execute: async ({ keywords, limit }) => {
    const grams = expandKeywords(keywords);
    const hits = await searchInteractionsByKeywords(grams, limit ?? 8);

    return {
      keywords: grams,
      total: hits.length,
      events: hits.map((hit) => ({
        at: hit.at,
        name: hit.contactName,
        kind: hit.kind,
        attrs: hit.attrs,
        background: hit.background,
        meeting: hit.meeting ?? null,
        matched: hit.hits,
      })),
      note: hits.length ? '' : '没有匹配的往事记录，可能是新的人。',
    };
  },
});
