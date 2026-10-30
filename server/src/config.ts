import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config as loadEnv } from 'dotenv';

const here = path.dirname(fileURLToPath(import.meta.url));

// 无论从哪个目录启动，都读 server/.env
loadEnv({ path: path.resolve(here, '../.env'), quiet: true });

function required(name: string, hint: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`[bizsnap] 缺少环境变量 ${name}。${hint}`);
    process.exit(1);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 8787),
  // 默认只听回环：模拟器够用，也不至于把没有鉴权的接口暴露到局域网。
  // 真机调试时用 HOST=0.0.0.0 启动，手机连 Mac 的局域网 IP。
  host: process.env.HOST ?? '127.0.0.1',

  deepseekApiKey: required('DEEPSEEK_API_KEY', '在 server/.env 里填 DEEPSEEK_API_KEY'),
  siliconflowApiKey: required('SILICONFLOW_API_KEY', '在 server/.env 里填 SILICONFLOW_API_KEY（嵌入必选）'),

  // 对话与视觉
  modelId: 'deepseek-flash',
  // 嵌入：中文 1024 维
  embeddingModelId: 'BAAI/bge-large-zh-v1.5',
  embeddingDim: 1024,

  timezone: 'Asia/Shanghai',
  defaultMeetingMinutes: 60,

  dbFile: path.resolve(here, '../bizsnap.db'),
} as const;

export const dbUrl = `file:${config.dbFile}`;

/** 所有会话共用同一个 resource（单机演示，无多用户） */
export const RESOURCE_ID = 'owner';
