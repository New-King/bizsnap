import { LibSQLStore } from '@mastra/libsql';
import { Memory } from '@mastra/memory';
import { db } from '../db/client.js';

/** 与业务表共用一个连接：同一个 bizsnap.db 文件 */
export const storage = new LibSQLStore({ id: 'bizsnap', client: db });

export const memory = new Memory({
  storage,
  options: {
    // 会话上下文只取最近 20 条，其余靠工具查库
    lastMessages: 20,
  },
});
