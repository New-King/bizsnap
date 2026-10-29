import { readFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { loadEnv, requireEnv } from './env.js';

loadEnv();

const apiKey = requireEnv('DEEPSEEK_API_KEY');
const model = 'deepseek-flash';

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf: Buffer): number {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([length, typeBuf, data, crc]);
}

/** 没有现成图片时，现场画一张 512×512 的示意图，用来验证模型确实能读图 */
function buildSamplePng(): Buffer {
  const width = 512;
  const height = 512;
  const bg = [245, 247, 250];
  const raw = Buffer.alloc(height * (width * 3 + 1));

  for (let y = 0; y < height; y += 1) {
    const rowStart = y * (width * 3 + 1);
    raw[rowStart] = 0;
    for (let x = 0; x < width; x += 1) {
      let color = bg;
      // 一条深色横条，像一行标题
      if (y >= 90 && y < 130 && x >= 60 && x < 300) color = [30, 34, 42];
      // 蓝色矩形
      if (y >= 200 && y < 320 && x >= 60 && x < 320) color = [91, 140, 255];
      // 右下角的小方块
      if (y >= 380 && y < 440 && x >= 360 && x < 420) color = [52, 199, 89];
      const offset = rowStart + 1 + x * 3;
      raw[offset] = color[0];
      raw[offset + 1] = color[1];
      raw[offset + 2] = color[2];
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const filePath = process.argv[2];
const image = filePath ? readFileSync(filePath) : buildSamplePng();
const mediaType = filePath?.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

console.log(filePath ? `使用图片 ${filePath}` : '使用现场生成的示意图（512×512 PNG）');

const response = await fetch('https://api.deepseek.com/chat/completions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${apiKey}`,
  },
  body: JSON.stringify({
    model,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: '用一句中文描述这张图里有什么颜色和形状。' },
          {
            type: 'image_url',
            image_url: { url: `data:${mediaType};base64,${image.toString('base64')}` },
          },
        ],
      },
    ],
  }),
});

if (!response.ok) {
  const body = await response.text();
  console.error(`视觉请求失败：HTTP ${response.status}`);
  console.error(body);
  console.error('\n如果提示不支持图片，把 server/src/llm.ts 换成：');
  console.error("  createOpenAICompatible({ name: 'deepseek', baseURL: 'https://api.deepseek.com', apiKey })");
  console.error("然后 .chatModel('deepseek-flash') 再跑一次。");
  process.exit(1);
}

const data = (await response.json()) as {
  choices?: { message?: { content?: string } }[];
};
console.log('模型回复：', data.choices?.[0]?.message?.content ?? '(空)');
console.log('图片输入可用。');
