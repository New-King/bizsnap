import { db } from '../db/client.js';

/** 清空后返回被清掉的名字，客户端据此删除写进系统通讯录 / 日历的条目 */
export type ResetSummary = {
  /** 本应用「创建联系人」写入过的人名（被「更新联系人」改过的原有联系人不算） */
  createdNames: string[];
  /** 本应用写进日历的会议标题 */
  meetingTitles: string[];
};

/** 设置页「清空数据」：只清业务数据，不动 Mastra 的会话表 */
export async function resetDemo(): Promise<ResetSummary> {
  // 先取名单，删完就查不到了
  const created = await db.execute({
    sql: `SELECT DISTINCT c.name AS name
          FROM contacts c
          JOIN interactions i ON i.contact_id = c.id
          WHERE i.kind = 'created'`,
    args: [],
  });
  const meetings = await db.execute({
    sql: `SELECT DISTINCT json_extract(meeting, '$.title') AS title
          FROM interactions
          WHERE kind = 'meeting' AND meeting IS NOT NULL`,
    args: [],
  });

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

  return {
    createdNames: created.rows.map((row) => String(row.name ?? '')).filter(Boolean),
    meetingTitles: meetings.rows.map((row) => String(row.title ?? '')).filter(Boolean),
  };
}
