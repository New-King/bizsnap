import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/** 脚本与 server 共用一份 key：不额外建配置文件 */
export function loadEnv(): void {
  const envPath = path.resolve(here, '../server/.env');
  if (!existsSync(envPath)) {
    console.error(`找不到 ${envPath}，先把 server/.env.example 复制成 server/.env 并填 key`);
    process.exit(1);
  }
  process.loadEnvFile(envPath);
}

export function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`缺少环境变量 ${name}（写在 server/.env）`);
    process.exit(1);
  }
  return value;
}

export const SERVER_URL = process.env.BIZSNAP_SERVER ?? 'http://127.0.0.1:8787';
