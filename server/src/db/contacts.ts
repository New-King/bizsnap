import { createHash, randomUUID } from 'node:crypto';
import type { Client, InStatement } from '@libsql/client';
import type { Attribute, ContactRecord, Interaction } from '../types.js';
import { cosine } from '../services/embedding.js';
import { db } from './client.js';

type Row = Record<string, unknown>;

const str = (v: unknown): string => (typeof v === 'string' ? v : v == null ? '' : String(v));
const num = (v: unknown): number => (typeof v === 'number' ? v : Number(v ?? 0));

/** 普通查询用 db，事务内传 Transaction，读写同一视图 */
export type Executor = {
  execute(stmt: InStatement): Promise<{ rows: Row[] }>;
};

const defaultExec: Executor = {
  execute: (stmt) => db.execute(stmt) as Promise<{ rows: Row[] }>,
};

export { defaultExec };

/** 姓名归一化：去空格与间隔号，用于匹配同一人 */
export function normalizeName(name: string): string {
  return name.replace(/[\s·・.。]/g, '').trim();
}

export function contactIdOf(name: string): string {
  return createHash('sha1').update(normalizeName(name)).digest('hex').slice(0, 16);
}

function parseAttributes(raw: string): Attribute[] {
  try {
    const parsed = JSON.parse(raw) as Attribute[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function rowToContact(row: Row): ContactRecord {
  return {
    id: str(row.id),
    name: str(row.name),
    phone: str(row.phone),
    email: str(row.email),
    attributes: parseAttributes(str(row.attributes)),
    searchCurrent: str(row.search_current),
    searchHistory: str(row.search_history),
    embedding: (row.embedding as string | null) ?? null,
    lastContactAt: (row.last_contact_at as string | null) ?? null,
    interactionCount: num(row.interaction_count),
    createdAt: str(row.created_at),
    updatedAt: str(row.updated_at),
  };
}

export async function listContacts(exec: Executor = defaultExec): Promise<ContactRecord[]> {
  const { rows } = await exec.execute('SELECT * FROM contacts ORDER BY updated_at DESC');
  return rows.map(rowToContact);
}

export async function getContactById(id: string, exec: Executor = defaultExec): Promise<ContactRecord | null> {
  const { rows } = await exec.execute({ sql: 'SELECT * FROM contacts WHERE id = ?', args: [id] });
  const row = rows[0];
  return row ? rowToContact(row) : null;
}

export async function findContactByName(name: string, exec: Executor = defaultExec): Promise<ContactRecord | null> {
  return getContactById(contactIdOf(name), exec);
}

export async function insertContact(record: ContactRecord, exec: Executor = defaultExec): Promise<void> {
  await exec.execute({
    sql: `INSERT INTO contacts
      (id, name, phone, email, attributes, search_current, search_history, embedding,
       last_contact_at, interaction_count, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    args: [
      record.id,
      record.name,
      record.phone,
      record.email,
      JSON.stringify(record.attributes),
      record.searchCurrent,
      record.searchHistory,
      record.embedding,
      record.lastContactAt,
      record.interactionCount,
      record.createdAt,
      record.updatedAt,
    ],
  });
}

export async function saveContact(record: ContactRecord, exec: Executor = defaultExec): Promise<void> {
  await exec.execute({
    sql: `UPDATE contacts SET
      name = ?, phone = ?, email = ?, attributes = ?, search_current = ?, search_history = ?,
      embedding = ?, last_contact_at = ?, interaction_count = ?, updated_at = ?
      WHERE id = ?`,
    args: [
      record.name,
      record.phone,
      record.email,
      JSON.stringify(record.attributes),
      record.searchCurrent,
      record.searchHistory,
      record.embedding,
      record.lastContactAt,
      record.interactionCount,
      record.updatedAt,
      record.id,
    ],
  });
}

export type KeywordHit = { contact: ContactRecord; matchedIn: 'now' | 'history' };

/**
 * 关键词检索：先查当前值列，再查历史值列。
 * 姓名、电话、公司都在这两列的文本里，用 LIKE 覆盖。
 */
export async function searchByKeyword(keyword: string, exec: Executor = defaultExec): Promise<KeywordHit[]> {
  const q = keyword.trim();
  if (!q) return [];
  const like = `%${q}%`;

  const current = await exec.execute({
    sql: 'SELECT * FROM contacts WHERE search_current LIKE ? LIMIT 20',
    args: [like],
  });
  const history = await exec.execute({
    sql: 'SELECT * FROM contacts WHERE search_history LIKE ? LIMIT 20',
    args: [like],
  });

  const hits = new Map<string, KeywordHit>();
  for (const row of current.rows) {
    const contact = rowToContact(row);
    hits.set(contact.id, { contact, matchedIn: 'now' });
  }
  for (const row of history.rows) {
    const contact = rowToContact(row);
    if (!hits.has(contact.id)) hits.set(contact.id, { contact, matchedIn: 'history' });
  }
  return [...hits.values()];
}

/** 向量兜底：把 query 嵌入后与全表比对，取相似度最高的几个 */
export async function searchByEmbedding(
  queryEmbedding: number[],
  limit = 5,
  minScore = 0.45,
  exec: Executor = defaultExec,
): Promise<{ contact: ContactRecord; score: number }[]> {
  const { rows } = await exec.execute('SELECT * FROM contacts WHERE embedding IS NOT NULL');
  const scored = rows
    .map((row) => {
      const contact = rowToContact(row);
      let vec: number[] = [];
      try {
        vec = JSON.parse(contact.embedding ?? '[]') as number[];
      } catch {
        vec = [];
      }
      return { contact, score: vec.length ? cosine(queryEmbedding, vec) : 0 };
    })
    .filter((item) => item.score >= minScore)
    .sort((a, b) => b.score - a.score);
  return scored.slice(0, limit);
}

export async function insertInteraction(
  interaction: Interaction,
  exec: Executor = defaultExec,
): Promise<void> {
  await exec.execute({
    sql: `INSERT INTO interactions
      (id, contact_id, group_id, at, kind, source, attrs, background, meeting, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    args: [
      interaction.id,
      interaction.contactId,
      interaction.groupId,
      interaction.at,
      interaction.kind,
      interaction.source,
      JSON.stringify(interaction.attrs),
      interaction.background,
      interaction.meeting ? JSON.stringify(interaction.meeting) : null,
      new Date().toISOString(),
    ],
  });
}

export async function listInteractions(
  contactId: string,
  limit = 8,
  exec: Executor = defaultExec,
): Promise<Interaction[]> {
  const { rows } = await exec.execute({
    sql: 'SELECT * FROM interactions WHERE contact_id = ? ORDER BY at DESC LIMIT ?',
    args: [contactId, limit],
  });
  return rows.map((row) => ({
    id: str(row.id),
    contactId: str(row.contact_id),
    groupId: str(row.group_id),
    at: str(row.at),
    kind: str(row.kind) as Interaction['kind'],
    source: str(row.source) as Interaction['source'],
    attrs: JSON.parse(str(row.attrs) || '[]') as string[],
    background: str(row.background),
    meeting: row.meeting ? (JSON.parse(str(row.meeting)) as Interaction['meeting']) : undefined,
  }));
}

export function newId(): string {
  return randomUUID();
}

export type { Client };
