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
  /** 派生列：只对「姓名 + 各属性当前值」嵌入（见 embeddingTextOf），JSON 数组文本；历史值不进向量 */
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
  payload: CreateContactPayload | UpdateContactPayload | CreateMeetingPayload;
};

/**
 * 一轮里模型做了什么，按发生顺序排列：思考片段 / 一次工具调用。
 * 只用于界面展示（链路感），不参与业务判断。
 */
export type TraceStep =
  | { kind: 'reasoning'; text: string }
  | {
      kind: 'tool';
      /** 与模型侧 toolCallId 一致，结果回来时按它找回这一步 */
      id: string;
      tool: string;
      /** 中文短标签，如「查联系人」 */
      label: string;
      /** 这次调用的关键入参，如人名、会议标题 */
      detail?: string;
      status: 'running' | 'ok' | 'error';
    };

export type ChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text?: string;
  imageBase64?: string;
  cards?: CardDraft[];
  /** 这一轮的思考与工具链路；老消息没有这个字段 */
  trace?: TraceStep[];
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
