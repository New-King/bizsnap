import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { findContactByName, newId } from '../../db/contacts.js';
import type { CardDraft, CreateContactPayload } from '../../types.js';

export const createContact = createTool({
  id: 'create_contact',
  description:
    '整理一条创建联系人的记录：姓名必填，其余字段能确定就填。',
  inputSchema: z.object({
    name: z.string().min(1).describe('姓名，必填'),
    phone: z.string().optional().describe('手机号或座机'),
    email: z.string().optional(),
    industry: z.string().optional().describe('行业，如 建筑设计、跨境电商'),
    company: z.string().optional(),
    position: z.string().optional().describe('职位'),
    project: z.string().optional().describe('正在合作或讨论的项目'),
    relation: z.string().optional().describe('关系，如 客户、供应商、前同事'),
  }),
  execute: async (input) => {
    const existed = await findContactByName(input.name);
    if (existed) {
      return {
        error: `库里已有「${existed.name}」，不要新建。需要改信息请调用 update_contact。`,
      };
    }

    const payload: CreateContactPayload = { name: input.name };
    for (const key of ['phone', 'email', 'industry', 'company', 'position', 'project', 'relation'] as const) {
      const value = input[key]?.trim();
      if (value) payload[key] = value;
    }

    const draft: CardDraft = {
      id: newId(),
      kind: 'create_contact',
      payload,
    };
    return { draft };
  },
});
