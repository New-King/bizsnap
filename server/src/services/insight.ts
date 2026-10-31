import { streamText } from 'ai';
import { chatModel } from '../llm.js';
import { renderTimeline } from './attributes.js';
import type { ContactRecord, Interaction } from '../types.js';

/** 确认之后才有洞察：输入是刚写入的事件 + 该联系人的完整时间线 */
export type InsightSource = {
  contact: ContactRecord;
  events: Interaction[];
  justWritten: Interaction[];
};

function renderEvent(event: Interaction): string {
  const parts = [`${event.at} ${event.kind}`, event.attrs.length ? `改动：${event.attrs.join('、')}` : ''];
  if (event.meeting) {
    parts.push(
      `会议：${event.meeting.title} ${event.meeting.startTime} 参与：${event.meeting.participants.join('、')}`,
    );
  }
  if (event.background) parts.push(`原因：${event.background}`);
  return `- ${parts.filter(Boolean).join('；')}`;
}

/** 本次确认里没写成的卡片：卡片只显示类型，为什么没成只能由文字交代 */
export type ConfirmFailure = {
  label: string;
  who: string;
  reason: string;
};

function renderFailures(failures: ConfirmFailure[]): string {
  return failures
    .map((item) => `- ${item.label}${item.who ? `（${item.who}）` : ''}：${item.reason}`)
    .join('\n');
}

const FAILURE_RULES = `硬性要求：
- 只复述上面给出的原因，不推测、不补全、不换个说法解释
- 说清哪张没成、卡在哪一步，再给一句用户可以怎么改
- 不道歉、不写「请重试」「有问题随时说」这类空话`;

/** 一张都没写成、也没有时间线可讲时，只生成这段说明 */
export function buildFailurePrompt(failures: ConfirmFailure[], okCount: number): string {
  const accepted = okCount > 0 ? `另有 ${okCount} 张已经写进去了。` : '这一轮一张都没写成。';
  return `本轮确认的结果：
${accepted}
没写成的卡片：
${renderFailures(failures)}

写 1 到 2 句中文：先说清哪张没成、卡在哪里，再说用户可以怎么改。${FAILURE_RULES}
- 不超过 80 字，不分段`;
}

export function buildInsightPrompt(
  { contact, events, justWritten }: InsightSource,
  failures: ConfirmFailure[] = [],
): string {
  const history = events.length ? events.map(renderEvent).join('\n') : '- 暂无历史事件';
  const fresh = justWritten.length ? justWritten.map(renderEvent).join('\n') : '- 无';
  const failed = failures.length ? `\n本次没写成的卡片：\n${renderFailures(failures)}\n` : '';

  return `联系人：${contact.name}
电话：${contact.phone || '未记录'}
邮箱：${contact.email || '未记录'}

属性时间线：
${renderTimeline(contact)}

最近往来：
${history}

本次刚刚写入：
${fresh}
${failed}
写 1 到 3 句中文：第一句陈述时间线上一个具体事实（认识多久、换过什么、上次见面距今多久），第二句给一条可执行的下一步建议（问什么、约谁、什么时候）。${failures.length ? '开头的第一句必须先交代没写成的那张卡：哪张、为什么。' : ''}
硬性要求：
- 只用上面存在的信息，不推测、不补全
- 不出现「依据」「根据记录」「综合来看」这类标签
- 不写「保持联系」「继续跟进」这类空话
- 不超过 120 字，不分段，不用列表`;
}

/**
 * 边生成边把片段交给调用方（路由直接推成 `text` 帧）。
 * 输出只用于展示，不写进会话消息。
 */
async function streamPrompt(prompt: string, onDelta: (delta: string) => void): Promise<string> {
  try {
    const result = streamText({ model: chatModel, prompt });
    let text = '';
    for await (const delta of result.textStream) {
      if (!delta) continue;
      text += delta;
      onDelta(delta);
    }
    return text.trim().replace(/\s*\n+\s*/g, ' ').slice(0, 200);
  } catch (error) {
    console.warn('[bizsnap] 整理回复生成失败：', (error as Error).message);
    return '';
  }
}

/** 确认成功的洞察；有卡片没写成时，第一句先交代那张 */
export function streamInsight(
  source: InsightSource,
  onDelta: (delta: string) => void,
  failures: ConfirmFailure[] = [],
): Promise<string> {
  return streamPrompt(buildInsightPrompt(source, failures), onDelta);
}

/** 一张都没写成（或找不到主联系人）：仍然让模型自己组织一句说明 */
export function streamFailureNote(
  failures: ConfirmFailure[],
  okCount: number,
  onDelta: (delta: string) => void,
): Promise<string> {
  if (!failures.length) return Promise.resolve('');
  return streamPrompt(buildFailurePrompt(failures, okCount), onDelta);
}
