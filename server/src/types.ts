export type AttributeType = 'industry' | 'company' | 'position' | 'project' | 'relation';

/** 一条属性 = 一条完整时间线，当前值与历史值都在这里 */
export type Attribute = {
  type: AttributeType;
  value: string;
  /** 当前值生效日，YYYY-MM-DD */
  since: string;
  /** 旧值，区间不重叠，最多 10 段 */
  history: { from: string; to: string; value: string }[];
};

export type ContactRecord = {
  id: string;
  name: string;
  phone: string;
  email: string;
  attributes: Attribute[];
  /** 派生列：姓名 + 各属性当前值，空格分隔 */
  searchCurrent: string;
  /** 派生列：各属性历史值，空格分隔 */
  searchHistory: string;
  /** 派生列：对 searchCurrent + searchHistory 拼成一句后嵌入，JSON 数组文本 */
  embedding: string | null;
  lastContactAt: string | null;
  interactionCount: number;
  createdAt: string;
  updatedAt: string;
};

export type InteractionKind = 'created' | 'updated' | 'meeting';
export type InteractionSource = 'image' | 'text' | 'both';

export type MeetingPayload = {
  title: string;
  /** 带时区偏移的 ISO 8601，如 2026-11-04T15:00:00+08:00 */
  startTime: string;
  endTime: string;
  location: string;
  participants: string[];
};

export type Interaction = {
  id: string;
  contactId: string;
  /** 同一次确认产生的多条共享 */
  groupId: string;
  at: string;
  kind: InteractionKind;
  source: InteractionSource;
  /** 本次动了哪些属性名，如 ['company'] */
  attrs: string[];
  /** 为什么；只复述输入里出现的原因，没有则空字符串 */
  background: string;
  meeting?: MeetingPayload;
};

export type CardKind = 'create_contact' | 'update_contact' | 'create_meeting';

export type CreateContactPayload = {
  name: string;
  phone?: string;
  email?: string;
  industry?: string;
  company?: string;
  position?: string;
  project?: string;
  relation?: string;
};

export type UpdateContactPayload = {
  targetName: string;
  changes: Partial<Omit<CreateContactPayload, 'name'>>;
};

export type CreateMeetingPayload = {
  title: string;
  startTime: string;
  endTime: string;
  location?: string;
  participants: string[];
  remark?: string;
};

export type CardDraft = {
  id: string;
  kind: CardKind;
  /** 由模型给出的原因，confirm 时校验后才写进 interaction.background */
  reason?: string;
  payload: CreateContactPayload | UpdateContactPayload | CreateMeetingPayload;
};

export type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text?: string;
  imageBase64?: string;
  cards?: CardDraft[];
  createdAt: string;
};

export type ThreadSummary = {
  id: string;
  title: string;
  contactName: string;
  lastMessage: string;
  updatedAt: string;
};

export type DeviceContactSnapshot = {
  name: string;
  company?: string;
  position?: string;
  phones?: string[];
};

/** search_contact 的候选 */
export type ContactCandidate = {
  id: string;
  name: string;
  /** 当前值快照，如 { company: 'C 公司' } */
  now: Record<string, string>;
  /** 可读时间线，直接拼进模型上下文 */
  timeline: string;
  matchedIn: 'now' | 'history' | 'semantic';
  inDevice: boolean;
};
