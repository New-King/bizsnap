import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { listRecentContacts } from '../../db/contacts.js';
import { currentValue } from '../../services/attributes.js';

function daysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

export const listContacts = createTool({
  id: 'list_contacts',
  description:
    '按最近一次往来倒序列出联系人的姓名、公司、职位。问「有哪些客户」「最近联系过谁」「手上都有谁」时用它列名单；要某个人的电话、关系、项目等细节用 search_contact。',
  inputSchema: z.object({
    days: z
      .number()
      .int()
      .min(1)
      .max(3650)
      .optional()
      .describe('只看最近 N 天有过往来的；省略表示不限时间'),
    limit: z.number().int().min(1).max(50).optional().describe('返回条数，默认 10'),
  }),
  execute: async ({ days, limit }) => {
    const contacts = await listRecentContacts({
      since: days ? daysAgo(days) : undefined,
      limit: limit ?? 10,
    });

    return {
      total: contacts.length,
      // 只给名单需要的最小信息：要细节交给 search_contact
      contacts: contacts.map((contact) => ({
        name: contact.name,
        company: currentValue(contact, 'company'),
        position: currentValue(contact, 'position'),
      })),
      note: contacts.length ? '' : '这个条件下没有联系人。',
    };
  },
});
