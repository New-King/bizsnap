import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { config } from '../../config.js';
import { newId } from '../../db/contacts.js';
import type { CardDraft, CreateMeetingPayload } from '../../types.js';

const ISO_WITH_OFFSET = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:\d{2}|Z)$/;

function isValidIso(value: string): boolean {
  return ISO_WITH_OFFSET.test(value) && !Number.isNaN(Date.parse(value));
}

function plusMinutes(iso: string, minutes: number): string {
  const date = new Date(iso);
  // 用固定偏移重排，保留原始时区写法
  const offsetMatch = iso.match(/([+-]\d{2}:\d{2}|Z)$/);
  const offset = offsetMatch?.[1] ?? '+08:00';
  if (offset === 'Z') return new Date(date.getTime() + minutes * 60_000).toISOString();
  const sign = offset.startsWith('-') ? -1 : 1;
  const [hh, mm] = offset.slice(1).split(':').map(Number);
  const offsetMinutes = sign * (hh * 60 + mm);
  const shifted = new Date(date.getTime() + minutes * 60_000 + offsetMinutes * 60_000);
  return shifted.toISOString().replace('Z', offset);
}

export const createMeeting = createTool({
  id: 'create_meeting',
  description:
    '整理一条会议安排：标题、开始时间、参会人。start_time / end_time 必须是带时区偏移的 ISO 8601。这里不写库，不会立刻生效。',
  inputSchema: z.object({
    title: z.string().min(1).describe('会议标题，如 与王建国确认二期方案'),
    start_time: z.string().describe('开始时间，ISO 8601 带偏移，如 2026-11-04T15:00:00+08:00'),
    end_time: z.string().optional().describe('结束时间，省略则按 1 小时'),
    participants: z.array(z.string()).min(1).describe('参会人姓名列表'),
    location: z.string().optional().describe('地点，线上会写会议方式'),
    remark: z.string().optional().describe('会议要谈什么'),
    reason: z.string().optional().describe('为什么约这次会，只复述输入里的原话'),
  }),
  execute: async (input) => {
    if (!isValidIso(input.start_time)) {
      return {
        error: `start_time「${input.start_time}」不是带时区偏移的 ISO 8601。请换算成如 2026-11-04T15:00:00+08:00 的形式。`,
      };
    }
    const endTime = input.end_time?.trim()
      ? input.end_time
      : plusMinutes(input.start_time, config.defaultMeetingMinutes);
    if (!isValidIso(endTime)) {
      return { error: `end_time「${endTime}」不是带时区偏移的 ISO 8601。` };
    }
    if (Date.parse(endTime) <= Date.parse(input.start_time)) {
      return { error: '结束时间必须晚于开始时间。' };
    }

    const payload: CreateMeetingPayload = {
      title: input.title,
      startTime: input.start_time,
      endTime,
      location: input.location?.trim() || '',
      participants: input.participants.map((name) => name.trim()).filter(Boolean),
      remark: input.remark?.trim() || undefined,
    };

    const draft: CardDraft = {
      id: newId(),
      kind: 'create_meeting',
      reason: input.reason?.trim() || undefined,
      payload,
    };
    return { draft };
  },
});
