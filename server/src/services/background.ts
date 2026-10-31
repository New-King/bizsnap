import { generateText } from 'ai';
import { chatModel } from '../llm.js';
import type { CardDraft } from '../types.js';

export type ChatLine = { role: string; text: string };

const RULES = `写 1 到 2 句中文，说清这条记录为什么存在：
- 先说起因：对话里说了什么、发生了什么事
- 再说这次要落地成什么
- 只用对话里出现的信息，不推测、不补全
- 不出现「用户」「模型」「输入」这类词，直接写事情本身
- 不用「已保存」「已记录」这类说法`;

function renderCard(card: CardDraft): string {
  const payload = card.payload as Record<string, unknown>;
  const fields = Object.entries(payload)
    .filter(([, value]) => typeof value === 'string' || Array.isArray(value))
    .map(([key, value]) => `${key}=${Array.isArray(value) ? value.join('/') : String(value)}`)
    .join('，');
  return `- [${card.id}] ${card.kind}：${fields}`;
}

function parseMap(raw: string): Map<string, string> {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  const result = new Map<string, string>();
  if (start < 0 || end <= start) return result;
  try {
    const parsed = JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>;
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === 'string' && value.trim()) result.set(key, value.trim());
    }
  } catch {
    // 解析不了就当没生成，调用方会退回动作摘要
  }
  return result;
}

/**
 * 每条记录一份背景：给模型看最近的对话与这批卡片，让它写清「因为什么、要落成什么」。
 * 拿不到结果时返回空表，调用方用动作摘要兜底。
 */
export async function generateBackgrounds(
  cards: CardDraft[],
  messages: ChatLine[],
): Promise<Map<string, string>> {
  if (!cards.length) return new Map();

  const conversation = messages
    .filter((line) => line.text.trim())
    .map((line) => `${line.role === 'user' ? '对方' : '我'}：${line.text.trim()}`)
    .join('\n');

  const prompt = `最近的对话：
${conversation || '（没有文字记录）'}

接下来要落地的记录：
${cards.map(renderCard).join('\n')}

${RULES}

只输出 JSON，形如 {"卡片id": "背景"}，每条记录一项，不要别的内容。`;

  const { text } = await generateText({ model: chatModel, prompt });
  return parseMap(text);
}
