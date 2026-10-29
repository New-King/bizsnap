import { SERVER_URL, loadEnv } from './env.js';

loadEnv();

const response = await fetch(`${SERVER_URL}/api/demo/seed`, { method: 'POST' });
if (!response.ok) {
  console.error(`灌数据失败：HTTP ${response.status}`);
  console.error(await response.text());
  console.error(`先确认服务已启动：cd server && pnpm dev（当前地址 ${SERVER_URL}）`);
  process.exit(1);
}

const result = (await response.json()) as { contacts: number; interactions: number };
console.log(`新建联系人 ${result.contacts} 位，事件 ${result.interactions} 条。`);
console.log('其中李静保留了「做过跨境支付、已转岗」的时间线，用于演示跨会话找回。');
