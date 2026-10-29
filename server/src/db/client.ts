import { createClient } from '@libsql/client';
import { dbUrl } from '../config.js';

/** 整个进程共用一个连接：业务表与 Mastra memory 都走它 */
export const db = createClient({ url: dbUrl });
