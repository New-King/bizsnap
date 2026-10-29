import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { findContactByName, newId } from '../../db/contacts.js';
import { currentValue } from '../../services/attributes.js';
import type { AttributeType, CardDraft, UpdateContactPayload } from '../../types.js';

const FIELD_TO_ATTR: Record<string, AttributeType> = {
  industry: 'industry',
  company: 'company',
  position: 'position',
  project: 'project',
  relation: 'relation',
};

export const updateContact = createTool({
  id: 'update_contact',
  description:
    '生成一张「更新联系人」卡片草案，只写这次要改的字段。目标必须已经存在于库里（先用 search_contact 或 get_contact_history 确认）。不写库：用户确认后才生效。',
  inputSchema: z.object({
    target_name: z.string().min(1).describe('要改的人，需与库里姓名一致'),
    phone: z.string().optional(),
    email: z.string().optional(),
    industry: z.string().optional(),
    company: z.string().optional(),
    position: z.string().optional(),
    project: z.string().optional(),
    relation: z.string().optional(),
    reason: z.string().optional().describe('为什么改，只复述输入里的原话'),
  }),
  execute: async (input) => {
    const contact = await findContactByName(input.target_name);
    if (!contact) {
      return {
        error: `库里没有「${input.target_name}」。确认姓名，或改用 create_contact 新建。`,
      };
    }

    const changes: UpdateContactPayload['changes'] = {};
    for (const key of ['phone', 'email', 'industry', 'company', 'position', 'project', 'relation'] as const) {
      const next = input[key]?.trim();
      if (!next) continue;
      const attrType = FIELD_TO_ATTR[key];
      const previous = attrType ? currentValue(contact, attrType) : (key === 'phone' ? contact.phone : contact.email);
      if (previous === next) continue;
      changes[key] = next;
    }

    if (!Object.keys(changes).length) {
      return {
        error: `「${contact.name}」的这些值没有变化，不需要出卡。若信息确实不同，请核对后重试。`,
      };
    }

    const payload: UpdateContactPayload = { targetName: contact.name, changes };
    const card: CardDraft = {
      id: newId(),
      kind: 'update_contact',
      reason: input.reason?.trim() || undefined,
      payload,
    };
    return { card, current: { company: currentValue(contact, 'company'), position: currentValue(contact, 'position') } };
  },
});
