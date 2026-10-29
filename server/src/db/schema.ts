import { db } from './client.js';

/**
 * 建业务表（幂等）。Mastra memory 自己的表由 LibSQLStore 初始化，前缀 mastra_，不会冲突。
 */
export async function ensureSchema(): Promise<void> {
  await db.batch(
    [
      `CREATE TABLE IF NOT EXISTS contacts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        attributes TEXT NOT NULL DEFAULT '[]',
        search_current TEXT NOT NULL DEFAULT '',
        search_history TEXT NOT NULL DEFAULT '',
        embedding TEXT,
        last_contact_at TEXT,
        interaction_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS interactions (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        at TEXT NOT NULL,
        kind TEXT NOT NULL,
        source TEXT NOT NULL,
        attrs TEXT NOT NULL DEFAULT '[]',
        background TEXT NOT NULL DEFAULT '',
        meeting TEXT,
        created_at TEXT NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS idx_interactions_contact ON interactions(contact_id, at DESC)`,
      `CREATE TABLE IF NOT EXISTS threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        contact_name TEXT NOT NULL DEFAULT '',
        last_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        image_base64 TEXT,
        cards TEXT,
        created_at TEXT NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id, created_at)`,
      `CREATE TABLE IF NOT EXISTS confirmed_cards (
        card_id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        at TEXT NOT NULL
      )`,
    ],
    'write',
  );
}
