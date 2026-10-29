import { generateText } from 'ai';
import { chatModel } from '../llm.js';
import { renderTimeline } from './attributes.js';
import type { ContactRecord, Interaction } from '../types.js';

function renderEvent(event: Interaction): string {
  const parts = [`${event.at} ${event.kind}`, event.attrs.length ? `改动：${event.attrs.join('、')}` : ''];
  if (event.meeting) {
    parts.push(`会议：${event.meeting.title} ${event.meeting.startTime} 参与：${event.meeting.participants.join('、')}`);
  }
  if (event.background) parts.push(`原因：${event.background}`);
  return `- ${parts.filter(Boolean).join('；')}`;
}

/**
 * 用户确认之后才生成：输入是刚写入的事件 + 该联系人的完整时间线。
 * 只在界面上展示，不写进会话消息。
 */
export async function generateInsight(
  contact: ContactRecord,
  events: Interaction[],
  justWritten: Interaction[],
): Promise<string> {
  const history = events.length ? events.map(renderEvent).join('\n') : '- 暂无历史事件';
  const fresh = justWritten.length ? justWritten.map(renderEvent).join('\n') : '- 无';

  const prompt = `联系人：${contact.name}
电话：${contact.phone || '未记录'}
邮箱：${contact.email || '未记录'}

属性时间线：
${renderTimeline(contact)}

最近往来：
${history}

本次刚刚写入：
${fresh}

写 1 到 3 句中文：第一句陈述时间线上一个具体事实（认识多久、换过什么、上次见面距今多久），第二句给一条可执行的下一步建议（问什么、约谁、什么时候）。
硬性要求：
- 只用上面存在的信息，不推测、不补全
- 不出现「依据」「根据记录」「综合来看」这类标签
- 不写「保持联系」「继续跟进」这类空话
- 不超过 120 字，不分段，不用列表`;

  try {
    const { text } = await generateText({ model: chatModel, prompt });
    return text.trim().replace(/\s*\n+\s*/g, ' ').slice(0, 200);
  } catch (error) {
    console.warn('[bizsnap] 洞察生成失败：', (error as Error).message);
    return '';
  }
}
