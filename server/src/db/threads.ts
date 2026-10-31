import { randomUUID } from 'node:crypto';
import type { CardDraft, ChatMessage, ThreadSummary, TraceStep } from '../types.js';
import { db } from './client.js';

type Row = Record<string, unknown>;
const str = (v: unknown): string => (typeof v === 'string' ? v : v == null ? '' : String(v));

export async function createThread(title = ''): Promise<string> {
  const id = randomUUID();
  const now = new Date().toISOString();
  await db.execute({
    sql: 'INSERT INTO threads (id, title, contact_name, last_message, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    args: [id, title, '', '', now, now],
  });
  return id;
}

export async function listThreads(): Promise<ThreadSummary[]> {
  const { rows } = await db.execute('SELECT * FROM threads ORDER BY updated_at DESC');
  return rows.map((row: Row) => ({
    id: str(row.id),
    title: str(row.title),
    contactName: str(row.contact_name),
    lastMessage: str(row.last_message),
    updatedAt: str(row.updated_at),
  }));
}

export async function getThread(id: string): Promise<ThreadSummary | null> {
  const { rows } = await db.execute({ sql: 'SELECT * FROM threads WHERE id = ?', args: [id] });
  const row = rows[0];
  if (!row) return null;
  return {
    id: str(row.id),
    title: str(row.title),
    contactName: str(row.contact_name),
    lastMessage: str(row.last_message),
    updatedAt: str(row.updated_at),
  };
}

export async function updateThread(
  id: string,
  patch: { title?: string; contactName?: string; lastMessage?: string },
): Promise<void> {
  const current = await getThread(id);
  if (!current) return;
  await db.execute({
    sql: 'UPDATE threads SET title = ?, contact_name = ?, last_message = ?, updated_at = ? WHERE id = ?',
    args: [
      patch.title ?? current.title,
      patch.contactName ?? current.contactName,
      patch.lastMessage ?? current.lastMessage,
      new Date().toISOString(),
      id,
    ],
  });
}

export async function deleteThread(id: string): Promise<void> {
  await db.batch(
    [
      { sql: 'DELETE FROM messages WHERE thread_id = ?', args: [id] },
      { sql: 'DELETE FROM threads WHERE id = ?', args: [id] },
    ],
    'write',
  );
}

export async function insertMessage(
  threadId: string,
  message: Omit<ChatMessage, 'createdAt'> & { createdAt?: string },
): Promise<ChatMessage> {
  const createdAt = message.createdAt ?? new Date().toISOString();
  await db.execute({
    sql: 'INSERT INTO messages (id, thread_id, role, text, image_base64, cards, trace, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    args: [
      message.id,
      threadId,
      message.role,
      message.text ?? '',
      message.imageBase64 ?? null,
      message.cards ? JSON.stringify(message.cards) : null,
      message.trace?.length ? JSON.stringify(message.trace) : null,
      createdAt,
    ],
  });
  const preview = message.cards?.length
    ? message.text ?? ''
    : (message.text ?? '已发送');
  await updateThread(threadId, { lastMessage: preview.slice(0, 60) });
  return { ...message, createdAt };
}

export async function listMessages(threadId: string): Promise<ChatMessage[]> {
  const { rows } = await db.execute({
    sql: 'SELECT * FROM messages WHERE thread_id = ? ORDER BY created_at ASC',
    args: [threadId],
  });
  return rows.map((row: Row) => ({
    id: str(row.id),
    role: str(row.role) as ChatMessage['role'],
    text: str(row.text) || undefined,
    imageBase64: (row.image_base64 as string | null) ?? undefined,
    cards: row.cards ? (JSON.parse(str(row.cards)) as CardDraft[]) : undefined,
    trace: row.trace ? (JSON.parse(str(row.trace)) as TraceStep[]) : undefined,
    createdAt: str(row.created_at),
  }));
}

/** background 的依据：这个会话最近几条消息的正文（user 与 assistant 都算） */
export async function getRecentText(threadId: string, limit = 6): Promise<string> {
  const messages = await listMessages(threadId);
  const texts = messages
    .map((message) => (message.text ?? '').trim())
    .filter((text) => text.length > 0)
    .slice(-limit);
  return texts.join('\n');
}

/** background 校验要用：本轮用户说过的话 */
export async function getLastUserText(threadId: string): Promise<string> {
  const message = await getLastUserMessage(threadId);
  return message.text;
}

export async function getLastUserMessage(
  threadId: string,
): Promise<{ text: string; hasImage: boolean }> {
  const { rows } = await db.execute({
    sql: "SELECT text, image_base64 FROM messages WHERE thread_id = ? AND role = 'user' ORDER BY created_at DESC LIMIT 1",
    args: [threadId],
  });
  return { text: str(rows[0]?.text), hasImage: Boolean(rows[0]?.image_base64) };
}

/** agent 调用失败时把刚存的用户消息撤掉，避免重试后留下两条一样的 */
export async function deleteMessage(id: string): Promise<void> {
  await db.execute({ sql: 'DELETE FROM messages WHERE id = ?', args: [id] });
}

/** 卡片确认后折叠成「已写入」：刷新页面也保持折叠 */
export async function markCardsConfirmed(threadId: string, cardIds: string[]): Promise<void> {
  if (!cardIds.length) return;
  const at = new Date().toISOString();
  await db.batch(
    cardIds.map((cardId) => ({
      sql: 'INSERT OR REPLACE INTO confirmed_cards (card_id, thread_id, at) VALUES (?, ?, ?)',
      args: [cardId, threadId, at],
    })),
    'write',
  );
}

export async function listConfirmedCardIds(threadId: string): Promise<string[]> {
  const { rows } = await db.execute({
    sql: 'SELECT card_id FROM confirmed_cards WHERE thread_id = ?',
    args: [threadId],
  });
  return rows.map((row: Row) => str(row.card_id));
}

/** 洞察生成要用：本轮之前最近一条 assistant 文本 */
export async function getLastAssistantText(threadId: string): Promise<string> {
  const { rows } = await db.execute({
    sql: "SELECT text FROM messages WHERE thread_id = ? AND role = 'assistant' ORDER BY created_at DESC LIMIT 1",
    args: [threadId],
  });
  return str(rows[0]?.text);
}
