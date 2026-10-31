import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { listInteractionsByFilter } from '../../db/contacts.js';

function daysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

export const listInteractions = createTool({
  id: 'list_interactions',
  description:
    '按时间列出往来事件：谁、什么时候、什么事（新建联系人 / 资料更新 / 会议）。问「最近有什么会议」「这周见过谁」「最近工作情况」时用它；凭一句模糊描述回忆往事用 search_interactions。',
  inputSchema: z.object({
    kind: z
      .enum(['created', 'updated', 'meeting', 'any'])
      .optional()
      .describe('事件类型：meeting 只看会议，any 表示全部，默认 any'),
    days: z.number().int().min(1).max(3650).optional().describe('最近多少天内，默认 30'),
    name: z.string().optional().describe('只看某个人的事件，姓名需与库里一致'),
    limit: z.number().int().min(1).max(50).optional().describe('返回条数，默认 10'),
  }),
  execute: async ({ kind, days, name, limit }) => {
    const events = await listInteractionsByFilter({
      kind: kind ?? 'any',
      since: daysAgo(days ?? 30),
      contactName: name,
      limit: limit ?? 10,
    });

    return {
      kind: kind ?? 'any',
      days: days ?? 30,
      total: events.length,
      events: events.map((event) => ({
        at: event.at,
        name: event.contactName,
        kind: event.kind,
        attrs: event.attrs,
        background: event.background,
        meeting: event.meeting ?? null,
      })),
      note: events.length ? '' : '这个时间范围内没有记录。',
    };
  },
});
