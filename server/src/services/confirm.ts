import { db } from '../db/client.js';
import {
  contactIdOf,
  findContactByName,
  insertContact,
  insertInteraction,
  listInteractions,
  newId,
  saveContact,
} from '../db/contacts.js';
import { getLastUserMessage, getThread, listConfirmedCardIds, updateThread } from '../db/threads.js';
import type {
  AttributeType,
  CardDraft,
  CardKind,
  ContactRecord,
  CreateContactPayload,
  CreateMeetingPayload,
  Interaction,
  InteractionSource,
  UpdateContactPayload,
} from '../types.js';
import { applyChange, currentValue, localDate } from './attributes.js';
import { buildSearchColumns, computeContactEmbedding } from './embedding.js';
import type { InsightSource } from './insight.js';

const ATTR_FIELDS: [keyof CreateContactPayload, AttributeType][] = [
  ['industry', 'industry'],
  ['company', 'company'],
  ['position', 'position'],
  ['project', 'project'],
  ['relation', 'relation'],
];

export type WrittenCard = {
  cardId: string;
  kind: CardKind;
  contactName: string;
  background: string;
  ok: boolean;
  error?: string;
};

type CardPlan = {
  cardId: string;
  kind: CardKind;
  contact: ContactRecord | null;
  isNew: boolean;
  interaction: Interaction | null;
  contactName: string;
  background: string;
  error?: string;
};

const normalize = (s: string) => s.replace(/[\s，。,.!?！？、；;：:"'「」“”()（）~-]/g, '');

/**
 * reason 必须能在本轮输入里找到依据：整段命中，或至少一半的三字片段命中。
 * 找不到就置空，宁可少一条原因，也不要编。
 */
function groundBackground(reason: string | undefined, input: string): string {
  const trimmed = (reason ?? '').trim();
  if (!trimmed) return '';
  const a = normalize(trimmed);
  const b = normalize(input);
  if (!a || !b) return '';
  if (b.includes(a)) return trimmed;

  const grams = new Set<string>();
  for (let i = 0; i + 3 <= a.length; i += 1) grams.add(a.slice(i, i + 3));
  if (!grams.size) return '';
  let hit = 0;
  for (const gram of grams) if (b.includes(gram)) hit += 1;
  if (hit / grams.size >= 0.5) return trimmed;

  console.warn(`[bizsnap] background 在本轮输入里找不到依据，已置空：「${trimmed}」`);
  return '';
}

function baseInteraction(params: {
  contactId: string;
  groupId: string;
  at: string;
  kind: Interaction['kind'];
  source: InteractionSource;
  attrs: string[];
  background: string;
  meeting?: Interaction['meeting'];
}): Interaction {
  return { id: newId(), ...params };
}

/** 把若干字段套到联系人上，返回实际发生变化的属性名 */
function applyFields(
  contact: ContactRecord,
  fields: Partial<CreateContactPayload>,
  date: string,
): string[] {
  const touched: string[] = [];
  for (const [field, type] of ATTR_FIELDS) {
    const value = fields[field]?.trim();
    if (!value) continue;
    if (currentValue(contact, type) === value) continue;
    contact.attributes = applyChange(contact.attributes, type, value, date);
    touched.push(type);
  }

  const phone = fields.phone?.trim();
  if (phone && phone !== contact.phone) {
    contact.phone = phone;
    touched.push('phone');
  }
  const email = fields.email?.trim();
  if (email && email !== contact.email) {
    contact.email = email;
    touched.push('email');
  }
  return touched;
}

/**
 * 确认落库：一个事务包住所有卡片。写入成功后重算检索列与向量，再生成洞察。
 */
export async function confirmCards(
  threadId: string,
  cards: CardDraft[],
): Promise<{
  ok: boolean;
  written: WrittenCard[];
  contactName: string;
  /** 洞察的输入；没有主联系人时为 null */
  insightSource: InsightSource | null;
}> {
  const thread = await getThread(threadId);
  if (!thread) {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }

  // 幂等：已经确认过的卡片不再写第二遍
  const done = new Set(await listConfirmedCardIds(threadId));
  const fresh = cards.filter((card) => !done.has(card.id));
  const skipped: WrittenCard[] = cards
    .filter((card) => done.has(card.id))
    .map((card) => ({
      cardId: card.id,
      kind: card.kind,
      contactName: thread.contactName,
      background: '',
      ok: true,
    }));

  const lastUser = await getLastUserMessage(threadId);
  const source: InteractionSource = lastUser.hasImage
    ? lastUser.text.trim()
      ? 'both'
      : 'image'
    : 'text';

  const groupId = newId();
  const at = new Date().toISOString();
  const date = localDate();

  const plans: CardPlan[] = [];
  let primaryName = thread.contactName;
  /** 本轮还没落库的联系人：会议卡要能找到同批新建的人 */
  const planned = new Map<string, ContactRecord>();

  // 第一轮：联系人卡（先定下本次会话的主联系人）
  for (const card of fresh) {
    if (card.kind !== 'create_contact' && card.kind !== 'update_contact') continue;
    const background = groundBackground(card.reason, lastUser.text);

    if (card.kind === 'create_contact') {
      const payload = card.payload as CreateContactPayload;
      const name = payload.name?.trim();
      if (!name) {
        plans.push({
          cardId: card.id,
          kind: card.kind,
          contact: null,
          isNew: false,
          interaction: null,
          contactName: '',
          background,
          error: '缺少姓名',
        });
        continue;
      }

      const existed = await findContactByName(name);
      const isNew = !existed;
      const contact: ContactRecord = existed
        ? { ...existed, attributes: [...existed.attributes] }
        : {
            id: contactIdOf(name),
            name,
            phone: '',
            email: '',
            attributes: [],
            searchCurrent: '',
            searchHistory: '',
            embedding: null,
            lastContactAt: at,
            interactionCount: 0,
            createdAt: at,
            updatedAt: at,
          };

      const touched = applyFields(contact, payload, date);
      contact.interactionCount += 1;
      contact.lastContactAt = at;
      contact.updatedAt = at;

      plans.push({
        cardId: card.id,
        kind: card.kind,
        contact,
        isNew,
        contactName: contact.name,
        background,
        interaction: baseInteraction({
          contactId: contact.id,
          groupId,
          at,
          kind: isNew ? 'created' : 'updated',
          source,
          attrs: touched,
          background,
        }),
      });
      planned.set(contact.id, contact);
      primaryName = primaryName || contact.name;
      continue;
    }

    // update_contact
    const payload = card.payload as UpdateContactPayload;
    const target = await findContactByName(payload.targetName ?? '');
    if (!target) {
      plans.push({
        cardId: card.id,
        kind: card.kind,
        contact: null,
        isNew: false,
        interaction: null,
        contactName: payload.targetName ?? '',
        background,
        error: `库里没有「${payload.targetName}」`,
      });
      continue;
    }

    const contact: ContactRecord = { ...target, attributes: [...target.attributes] };
    const touched = applyFields(contact, payload.changes ?? {}, date);
    contact.interactionCount += 1;
    contact.lastContactAt = at;
    contact.updatedAt = at;

    plans.push({
      cardId: card.id,
      kind: card.kind,
      contact,
      isNew: false,
      contactName: contact.name,
      background,
      interaction: baseInteraction({
        contactId: contact.id,
        groupId,
        at,
        kind: 'updated',
        source,
        attrs: touched,
        background,
      }),
    });
    primaryName = primaryName || contact.name;
  }

  // 第二轮：会议卡，挂在本次会话的主联系人名下
  for (const card of fresh) {
    if (card.kind !== 'create_meeting') continue;
    const payload = card.payload as CreateMeetingPayload;
    const background = groundBackground(card.reason, lastUser.text);
    const ownerName = primaryName || payload.participants?.[0] || '';
    const owner = ownerName
      ? planned.get(contactIdOf(ownerName)) ?? (await findContactByName(ownerName))
      : null;

    if (!owner) {
      plans.push({
        cardId: card.id,
        kind: card.kind,
        contact: null,
        isNew: false,
        interaction: null,
        contactName: ownerName,
        background,
        error: '当前会话还没有主联系人，先创建或更新联系人，再约会议',
      });
      continue;
    }

    const contact: ContactRecord = { ...owner, attributes: [...owner.attributes] };
    contact.interactionCount += 1;
    contact.lastContactAt = at;
    contact.updatedAt = at;

    plans.push({
      cardId: card.id,
      kind: card.kind,
      contact,
      isNew: false,
      contactName: contact.name,
      background,
      interaction: baseInteraction({
        contactId: contact.id,
        groupId,
        at,
        kind: 'meeting',
        source,
        attrs: [],
        background,
        meeting: {
          title: payload.title,
          startTime: payload.startTime,
          endTime: payload.endTime,
          location: payload.location ?? '',
          participants: payload.participants ?? [],
        },
      }),
    });
    // 只有会议卡时，主联系人也由这场会的主人确定
    primaryName = primaryName || contact.name;
  }

  // 落库：单事务
  const tx = await db.transaction('write');
  try {
    for (const plan of plans) {
      if (plan.error || !plan.contact || !plan.interaction) continue;
      if (plan.isNew) {
        await insertContact(plan.contact, tx);
      } else {
        await saveContact(plan.contact, tx);
      }
      await insertInteraction(plan.interaction, tx);
    }
    await tx.commit();
  } catch (error) {
    await tx.rollback();
    throw error;
  }

  // 派生物在事务外重算：嵌入要发网络请求，不该占着写锁
  const affected = new Map<string, ContactRecord>();
  for (const plan of plans) {
    if (!plan.error && plan.contact) affected.set(plan.contact.id, plan.contact);
  }
  for (const contact of affected.values()) {
    const columns = buildSearchColumns(contact);
    const embedding = await computeContactEmbedding(columns);
    await saveContact({ ...contact, ...columns, embedding, updatedAt: at });
  }

  const primary = primaryName ? affected.get(contactIdOf(primaryName)) ?? (await findContactByName(primaryName)) : null;

  if (primary && !thread.contactName) {
    await updateThread(threadId, {
      contactName: primary.name,
      title: thread.title || primary.name,
    });
  }

  const written: WrittenCard[] = [...skipped, ...plans.map((plan) => ({
    cardId: plan.cardId,
    kind: plan.kind,
    contactName: plan.contactName,
    background: plan.background,
    ok: !plan.error,
    error: plan.error,
  }))];

  // 洞察留给路由去流式生成，这里只准备输入
  let insightSource: InsightSource | null = null;
  if (primary) {
    const events = await listInteractions(primary.id, 8);
    const writtenInteractionIds = new Set(
      plans.filter((plan) => plan.contact?.id === primary.id).map((plan) => plan.interaction?.id),
    );
    insightSource = {
      contact: primary,
      events,
      justWritten: events.filter((event) => writtenInteractionIds.has(event.id)),
    };
  }

  return {
    ok: written.every((item) => item.ok),
    written,
    contactName: primary?.name ?? thread.contactName,
    insightSource,
  };
}
