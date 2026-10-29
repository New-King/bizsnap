import { contactIdOf, insertContact, insertInteraction, listInteractions, newId } from '../db/contacts.js';
import { db } from '../db/client.js';
import type { Attribute, AttributeType, ContactRecord, Interaction } from '../types.js';
import { buildSearchColumns, computeContactEmbedding } from './embedding.js';

function attr(
  type: AttributeType,
  value: string,
  since: string,
  history: Attribute['history'] = [],
): Attribute {
  return { type, value, since, history };
}

type DemoContact = {
  name: string;
  phone: string;
  email: string;
  attributes: Attribute[];
  interactions: Omit<Interaction, 'id' | 'contactId' | 'groupId'>[];
};

const DEMO: DemoContact[] = [
  {
    name: '王建国',
    phone: '13800000001',
    email: 'wangjianguo@hengai.example',
    attributes: [
      attr('industry', '建筑设计', '2024-03-01', [{ from: '2021-06-01', to: '2024-02-28', value: '房地产销售' }]),
      attr('company', '恒安设计院', '2024-03-01', [{ from: '2021-06-01', to: '2024-02-28', value: '恒宇地产' }]),
      attr('position', '合规总监', '2024-03-01', [{ from: '2021-06-01', to: '2024-02-28', value: '销售经理' }]),
      attr('project', '二期方案', '2026-09-10'),
      attr('relation', '客户', '2021-06-01'),
    ],
    interactions: [
      {
        at: '2026-09-10T10:20:00+08:00',
        kind: 'updated',
        source: 'image',
        attrs: ['project'],
        background: '客户提到二期方案要重新报价',
      },
      {
        at: '2026-06-18T15:00:00+08:00',
        kind: 'meeting',
        source: 'text',
        attrs: [],
        background: '',
        meeting: {
          title: '与王建国过一期验收',
          startTime: '2026-06-18T15:00:00+08:00',
          endTime: '2026-06-18T16:00:00+08:00',
          location: '恒安设计院 3 层会议室',
          participants: ['王建国'],
        },
      },
    ],
  },
  {
    name: '李静',
    phone: '13800000002',
    email: 'lijing@csea.example',
    attributes: [
      attr('industry', '跨境电商', '2023-05-01'),
      attr('company', 'C 公司', '2023-05-01'),
      attr('position', '运营总监', '2023-05-01'),
      // 做过跨境支付，2026-02 起转岗做供应链
      attr('project', '供应链优化', '2026-02-01', [{ from: '2025-03-01', to: '2026-01-31', value: '跨境支付' }]),
      attr('relation', '客户', '2023-05-01'),
    ],
    interactions: [
      {
        at: '2026-08-20T14:00:00+08:00',
        kind: 'meeting',
        source: 'text',
        attrs: [],
        background: '',
        meeting: {
          title: '与李静对齐供应链节奏',
          startTime: '2026-08-20T14:00:00+08:00',
          endTime: '2026-08-20T15:00:00+08:00',
          location: '线上',
          participants: ['李静'],
        },
      },
      {
        at: '2026-01-28T11:00:00+08:00',
        kind: 'meeting',
        source: 'image',
        attrs: [],
        background: '跨境支付上线前最后一次对账',
        meeting: {
          title: '跨境支付对账会',
          startTime: '2026-01-28T11:00:00+08:00',
          endTime: '2026-01-28T12:00:00+08:00',
          location: 'C 公司 12 层',
          participants: ['李静', '陈默'],
        },
      },
    ],
  },
  {
    name: '陈默',
    phone: '13800000003',
    email: 'chenmo@csea.example',
    attributes: [
      attr('industry', '跨境电商', '2026-02-01'),
      attr('company', 'C 公司', '2026-02-01'),
      attr('position', '支付产品负责人', '2026-02-01'),
      attr('project', '跨境支付', '2026-02-01'),
      attr('relation', '客户', '2026-02-01'),
    ],
    interactions: [
      {
        at: '2026-09-30T16:30:00+08:00',
        kind: 'created',
        source: 'image',
        attrs: ['company', 'position', 'project'],
        background: '李静转岗后由陈默接手跨境支付',
      },
    ],
  },
];

export async function seedDemo(): Promise<{ contacts: number; interactions: number }> {
  let contactCount = 0;
  let interactionCount = 0;
  const now = new Date().toISOString();

  for (const item of DEMO) {
    const id = contactIdOf(item.name);
    const existing = await db.execute({ sql: 'SELECT id FROM contacts WHERE id = ?', args: [id] });
    if (existing.rows.length) continue;

    const columns = buildSearchColumns({
      name: item.name,
      phone: item.phone,
      email: item.email,
      attributes: item.attributes,
    });
    const embedding = await computeContactEmbedding(columns);
    const lastAt = item.interactions[0]?.at ?? now;

    const contact: ContactRecord = {
      id,
      name: item.name,
      phone: item.phone,
      email: item.email,
      attributes: item.attributes,
      searchCurrent: columns.searchCurrent,
      searchHistory: columns.searchHistory,
      embedding,
      lastContactAt: lastAt,
      interactionCount: item.interactions.length,
      createdAt: now,
      updatedAt: now,
    };
    await insertContact(contact);
    contactCount += 1;

    const already = await listInteractions(id, 1);
    if (!already.length) {
      const groupId = newId();
      for (const event of item.interactions) {
        await insertInteraction({ ...event, id: newId(), contactId: id, groupId });
        interactionCount += 1;
      }
    }
  }

  return { contacts: contactCount, interactions: interactionCount };
}

/** 设置页「清空数据」：只清业务数据，不动 Mastra 的会话表 */
export async function resetDemo(): Promise<void> {
  await db.batch(
    [
      'DELETE FROM interactions',
      'DELETE FROM contacts',
      'DELETE FROM messages',
      'DELETE FROM threads',
      'DELETE FROM confirmed_cards',
      // 会话上下文也一起清掉，否则新会话会捞到旧上下文
      'DELETE FROM mastra_messages',
      'DELETE FROM mastra_thread_state',
      'DELETE FROM mastra_threads',
    ],
    'write',
  );
}
