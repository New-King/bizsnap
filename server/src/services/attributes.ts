import type { Attribute, AttributeType, ContactRecord } from '../types.js';

const MAX_HISTORY = 10;

/** 以 Asia/Shanghai 为准的 YYYY-MM-DD */
export function localDate(date: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
  return parts;
}

export function dayBefore(isoDate: string): string {
  const d = new Date(`${isoDate}T00:00:00+08:00`);
  d.setUTCDate(d.getUTCDate() - 1);
  return localDate(d);
}

/**
 * SCD2 封口：有新值时把旧值压进 history（区间右闭 = 新 since 前一天），
 * 值没变则不动。
 */
export function applyChange(
  attributes: Attribute[],
  type: AttributeType,
  rawValue: string,
  date: string = localDate(),
): Attribute[] {
  const value = rawValue.trim();
  if (!value) return attributes;

  const existing = attributes.find((attr) => attr.type === type);

  if (!existing) {
    return [...attributes, { type, value, since: date, history: [] }];
  }
  if (existing.value === value) {
    return attributes;
  }

  const history = [
    ...existing.history,
    { from: existing.since, to: dayBefore(date), value: existing.value },
  ];
  return attributes.map((attr) =>
    attr.type === type ? { type, value, since: date, history: collapse(history) } : attr,
  );
}

/** 超过 10 段就把最早的两段并成一段 */
function collapse(history: Attribute['history']): Attribute['history'] {
  const segments = [...history];
  while (segments.length > MAX_HISTORY) {
    const [oldest, next] = segments;
    segments.splice(0, 2, {
      from: oldest.from,
      to: next.to,
      value: oldest.value.startsWith('此前：') ? oldest.value : `此前：${oldest.value}`,
    });
  }
  return segments;
}

export function currentValue(contact: ContactRecord, type: AttributeType): string {
  return contact.attributes.find((attr) => attr.type === type)?.value ?? '';
}

export function currentValues(contact: ContactRecord): Record<string, string> {
  const result: Record<string, string> = {};
  for (const attr of contact.attributes) {
    if (attr.value) result[attr.type] = attr.value;
  }
  return result;
}

const LABELS: Record<AttributeType, string> = {
  industry: '行业',
  company: '公司',
  position: '职位',
  project: '项目',
  relation: '关系',
};

/** 给模型看的时间线文本：当前值 + 历史段 */
export function renderTimeline(contact: ContactRecord): string {
  const lines: string[] = [];
  for (const attr of contact.attributes) {
    if (!attr.value) continue;
    const label = LABELS[attr.type];
    const seg = attr.history
      .slice()
      .sort((a, b) => (a.from < b.from ? -1 : 1))
      .map((h) => `${h.from} 至 ${h.to} 为 ${h.value}`)
      .join('；');
    lines.push(seg ? `${label}：现为 ${attr.value}（${attr.since} 起）；此前 ${seg}` : `${label}：${attr.value}（${attr.since} 起）`);
  }
  if (!lines.length) lines.push('暂无属性记录');
  return lines.join('\n');
}
