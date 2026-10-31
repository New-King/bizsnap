import { generateText } from 'ai';
import { chatModel } from '../llm.js';
import type { CardDraft } from '../types.js';

export type ChatLine = { role: string; text: string };

const RULES = `写法：一句「用户说「原话片段」」，用户只是补充某个信息时就写「用户补充「原话片段」」；内容来自截图时写「截图里说「原话片段」」。
- 引号里必须是对话中出现过的原话，不改写、不概括
- 需要时说清这次落成什么，最多再加半句，例如「用户说「下周三下午三点约他聊聊二期验收」，记成会议」
- 不写分析、不解释、不出现「对话」「记录」「模型」这类词`;

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
