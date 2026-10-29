import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { findContactByName, listInteractions } from '../../db/contacts.js';
import { renderTimeline } from '../../services/attributes.js';

export const getContactHistory = createTool({
  id: 'get_contact_history',
  description:
    '取某个人的完整属性时间线与最近若干条往来事件（含每次的原因、会议信息）。search_contact 已经给出时间线时，只有需要更早的事件细节才调用它。',
  inputSchema: z.object({
    name: z.string().min(1).describe('联系人姓名，需与 search_contact 返回的姓名一致'),
    limit: z.number().int().min(1).max(30).optional().describe('返回最近多少条事件，默认 8'),
  }),
  execute: async ({ name, limit }) => {
    const contact = await findContactByName(name);
    if (!contact) {
      return {
        found: false as const,
        name,
        message: `库里没有「${name}」这个人，先确认姓名或改用 search_contact。`,
      };
    }

    const events = await listInteractions(contact.id, limit ?? 8);
    return {
      found: true as const,
      name: contact.name,
      phone: contact.phone,
      email: contact.email,
      timeline: renderTimeline(contact),
      interactionCount: contact.interactionCount,
      lastContactAt: contact.lastContactAt ?? '',
      events: events.map((event) => ({
        at: event.at,
        kind: event.kind,
        attrs: event.attrs,
        background: event.background,
        meeting: event.meeting ?? null,
      })),
    };
  },
});
