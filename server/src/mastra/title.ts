import { generateText } from 'ai';
import { chatModel } from '../llm.js';

/** 抽屉里一行放得下的长度 */
const MAX_LEN = 14;

function clean(raw: string): string {
  let text = raw.replace(/[\r\n]+/g, ' ').trim();
  // 模型偶尔自带引号、书名号与前缀
  text = text.replace(/^["'“”「」『』《》\s]+|["'“”「」『』《》\s]+$/g, '');
  text = text.replace(/^(标题|对话标题|会话标题)\s*[:：]\s*/, '');
  // 结尾标点一律去掉
  text = text.replace(/[。．.！!？?，,、；;：:~]+$/g, '').trim();
  return text.slice(0, MAX_LEN);
}

/**
 * 用首轮对话生成会话标题。失败由调用方吞掉，不能影响主流程。
 */
export async function generateTitle(userText: string, reply: string): Promise<string> {
  const context = `用户：${userText || '（发来一张截图）'}\n助手：${reply.slice(0, 200)}`;

  const { text } = await generateText({
    model: chatModel,
    temperature: 0.3,
    prompt: `给下面这段对话起一个标题。

要求：
- 6 到 12 个字，中文
- 概括这段对话在谈什么人、什么事
- 不要引号、不要句号，不要「对话」「咨询」「关于」这类空词
- 只输出标题本身，不要任何解释

${context}`,
  });

  return clean(text);
}
