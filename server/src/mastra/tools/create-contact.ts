import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { findContactByName, newId } from '../../db/contacts.js';
import type { CardDraft, CreateContactPayload } from '../../types.js';

export const createContact = createTool({
  id: 'create_contact',
  description:
    '生成一张「创建联系人」卡片草案。不写库：只有用户确认后才会真正落库并写入系统通讯录。出卡前必须先在正文里说清建谁、什么公司、什么职位。',
  inputSchema: z.object({
    name: z.string().min(1).describe('姓名，必填'),
    phone: z.string().optional().describe('手机号或座机'),
    email: z.string().optional(),
    industry: z.string().optional().describe('行业，如 建筑设计、跨境电商'),
    company: z.string().optional(),
    position: z.string().optional().describe('职位'),
    project: z.string().optional().describe('正在合作或讨论的项目'),
    relation: z.string().optional().describe('关系，如 客户、供应商、前同事'),
    reason: z.string().optional().describe('为什么要建这条记录，只复述输入里的原话'),
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

    const card: CardDraft = {
      id: newId(),
      kind: 'create_contact',
      reason: input.reason?.trim() || undefined,
      payload,
    };
    return { card };
  },
});
