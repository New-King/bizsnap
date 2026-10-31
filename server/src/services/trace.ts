import type { TraceStep } from '../types.js';

/** 工具名 → 界面上的中文短标签。新增工具时同步加一行 */
const LABELS: Record<string, string> = {
  search_contact: '查联系人',
  search_interactions: '查往来记录',
  get_contact_history: '查履历',
  list_contacts: '列联系人',
  list_interactions: '列往来',
  create_contact: '整理联系人',
  update_contact: '整理资料更新',
  create_meeting: '安排会议',
};

/** 从入参里挑一个能说明「这次在查谁 / 在记什么」的值 */
function detailOf(args: unknown): string | undefined {
  if (!args || typeof args !== 'object') return undefined;
  const record = args as Record<string, unknown>;
  for (const key of ['query', 'target_name', 'name', 'title']) {
    const value = record[key];
    if (typeof value === 'string' && value.trim()) return value.trim().slice(0, 40);
  }
  // 列事件时按类型显示，比空着更有信息量
  const kindLabels: Record<string, string> = {
    meeting: '会议',
    created: '新建',
    updated: '更新',
    any: '全部',
  };
  const kind = record.kind;
  if (typeof kind === 'string' && kindLabels[kind]) return kindLabels[kind];
  return undefined;
}

/**
 * 把 Mastra 的流事件收成一条可展示的链路：
 * 思考并成一段、连续的工具调用按顺序排。只做记录，不改任何业务判断。
 */
export class TraceRecorder {
  readonly steps: TraceStep[] = [];
  /** 当前正在累积的思考段；工具调用之后置空，下一段思考另起一块 */
  private reasoningIndex: number | null = null;
  private readonly toolIndex = new Map<string, number>();

  /** 思考逐字到达：并进同一段，界面侧也按 delta 追加 */
  reasoning(delta: string): void {
    if (!delta) return;
    const current = this.reasoningIndex === null ? undefined : this.steps[this.reasoningIndex];
    if (current && current.kind === 'reasoning') {
      current.text += delta;
      return;
    }
    this.steps.push({ kind: 'reasoning', text: delta });
    this.reasoningIndex = this.steps.length - 1;
  }

  toolCall(input: { toolCallId: string; toolName: string; args?: unknown }): TraceStep {
    const step: TraceStep = {
      kind: 'tool',
      id: input.toolCallId,
      tool: input.toolName,
      label: LABELS[input.toolName] ?? input.toolName,
      detail: detailOf(input.args),
      status: 'running',
    };
    this.steps.push(step);
    this.toolIndex.set(input.toolCallId, this.steps.length - 1);
    // 工具之后模型再思考，是新的一段，不要接在调用之前那段后面
    this.reasoningIndex = null;
    return step;
  }

  /** 结果回来：按 toolCallId 找回原来那一步，就地改状态 */
  toolResult(input: { toolCallId: string; isError?: boolean }, fallbackTool = ''): TraceStep {
    const index = this.toolIndex.get(input.toolCallId);
    if (index === undefined) {
      const step: TraceStep = {
        kind: 'tool',
        id: input.toolCallId,
        tool: fallbackTool,
        label: LABELS[fallbackTool] ?? (fallbackTool || '工具调用'),
        status: input.isError ? 'error' : 'ok',
      };
      this.steps.push(step);
      this.toolIndex.set(input.toolCallId, this.steps.length - 1);
      return step;
    }
    const step = this.steps[index];
    if (step.kind === 'tool') {
      step.status = input.isError ? 'error' : 'ok';
    }
    return this.steps[index];
  }

  /** 只留能看的那部分：空段、纯空白的思考不要拖进去 */
  snapshot(): TraceStep[] {
    return this.steps.filter((step) =>
      step.kind === 'reasoning' ? step.text.trim().length > 0 : true,
    );
  }
}
