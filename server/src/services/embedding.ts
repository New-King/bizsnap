import { createOpenAICompatible } from '@ai-sdk/openai-compatible';
import { embed } from 'ai';
import { config } from '../config.js';
import type { Attribute, ContactRecord } from '../types.js';

const siliconflow = createOpenAICompatible({
  name: 'siliconflow',
  baseURL: 'https://api.siliconflow.cn/v1',
  apiKey: config.siliconflowApiKey,
});

export const embeddingModel = siliconflow.embeddingModel(config.embeddingModelId);

export async function embedText(text: string): Promise<number[]> {
  const { embedding } = await embed({ model: embeddingModel, value: text });
  return embedding;
}

/** 余弦相似度：几百人的规模在 Node 侧算足够，不进向量库 */
export function cosine(a: number[], b: number[]): number {
  const len = Math.min(a.length, b.length);
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < len; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (!na || !nb) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

function currentValues(attributes: Attribute[]): string[] {
  return attributes.map((attr) => attr.value).filter(Boolean);
}

function historyValues(attributes: Attribute[]): string[] {
  const values: string[] = [];
  for (const attr of attributes) {
    for (const segment of attr.history) {
      // 「此前：」只是展示前缀，检索列里去掉
      values.push(segment.value.replace(/^此前：/, ''));
    }
  }
  return values;
}

/**
 * 检索列与嵌入输入都是派生物：只在 confirm 时重算，任何读取路径不许写。
 */
export function buildSearchColumns(contact: {
  name: string;
  phone: string;
  email: string;
  attributes: Attribute[];
}): { searchCurrent: string; searchHistory: string } {
  const current = [contact.name, contact.phone, contact.email, ...currentValues(contact.attributes)]
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();

  const history = historyValues(contact.attributes).filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();

  return { searchCurrent: current, searchHistory: history };
}

/**
 * 向量只描述「这个人现在是什么样」：姓名 + 5 个当前值。
 * 历史段不进向量 —— 一条向量只能代表一个主题，塞进多段旧值会把每段都稀释；
 * 往事交给 search_interactions 走关键词查事件记录。
 * 电话、邮箱是精确查找的活，进向量只是噪音，一起排除。
 */
export function embeddingTextOf(contact: { name: string; attributes: Attribute[] }): string {
  const values = contact.attributes.map((attr) => attr.value).filter(Boolean);
  return [contact.name, ...values].filter(Boolean).join(' ').trim();
}

/** 一人一条向量：只嵌当前状态 */
export async function computeContactEmbedding(contact: {
  name: string;
  attributes: Attribute[];
}): Promise<string | null> {
  const text = embeddingTextOf(contact);
  if (!text) return null;
  try {
    const vector = await embedText(text);
    return JSON.stringify(vector.map((v) => Number(v.toFixed(6))));
  } catch (error) {
    console.warn('[bizsnap] 嵌入失败，该联系人暂不参与语义检索：', (error as Error).message);
    return null;
  }
}

export function contactToEmbeddingInput(contact: ContactRecord): string {
  return embeddingTextOf(contact);
}
