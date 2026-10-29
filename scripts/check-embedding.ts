import { loadEnv, requireEnv } from './env.js';

loadEnv();

const apiKey = requireEnv('SILICONFLOW_API_KEY');
const model = 'BAAI/bge-large-zh-v1.5';

const response = await fetch('https://api.siliconflow.cn/v1/embeddings', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${apiKey}`,
  },
  body: JSON.stringify({ model, input: '李静负责跨境支付项目，现在转做供应链。' }),
});

if (!response.ok) {
  console.error(`嵌入请求失败：HTTP ${response.status}`);
  console.error(await response.text());
  process.exit(1);
}

const data = (await response.json()) as { data?: { embedding: number[] }[] };
const embedding = data.data?.[0]?.embedding ?? [];

console.log(`模型 ${model}`);
console.log(`维度 ${embedding.length}`);
console.log(`前 5 个值 ${embedding.slice(0, 5).map((v) => v.toFixed(4)).join(', ')}`);

if (embedding.length !== 1024) {
  console.error(`维度不是 1024（实际 ${embedding.length}），请确认模型没被换掉`);
  process.exit(1);
}

console.log('嵌入可用。');
