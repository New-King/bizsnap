import { Agent, type MastraLanguageModel } from '@mastra/core/agent';
import { chatModel } from '../llm.js';
import { memory, storage } from './storage.js';
import { buildPrompt } from './prompt.js';
import { createContact } from './tools/create-contact.js';
import { createMeeting } from './tools/create-meeting.js';
import { getContactHistory } from './tools/get-history.js';
import { searchContact } from './tools/search-contact.js';
import { updateContact } from './tools/update-contact.js';

/**
 * 只保留会话消息持久化 + lastMessages：跨会话的「人」的记忆走 contacts / interactions 两张表，
 * 不启用 workingMemory / semanticRecall（维度是「按人」，不是「按用户」）。
 */
export const bizAgent = new Agent({
  id: 'bizsnap',
  name: 'bizsnap',
  description: '商务 CRM 助手：读截图或文字，查人、查历史，出确认卡片',
  instructions: buildPrompt(),
  // ai@7 的 provider 类型与 Mastra 内部的 V4 结构类型字面不完全一致，运行时一致
  model: chatModel as unknown as MastraLanguageModel,
  // key 就是模型看到的工具名，与 inputSchema 的描述保持一致
  tools: {
    search_contact: searchContact,
    get_contact_history: getContactHistory,
    create_contact: createContact,
    update_contact: updateContact,
    create_meeting: createMeeting,
  },
  memory,
});

export { storage };
