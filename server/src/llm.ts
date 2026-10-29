import { createDeepSeek } from '@ai-sdk/deepseek';
import { config } from './config.js';

export const deepseek = createDeepSeek({ apiKey: config.deepseekApiKey });

/** 对话、视觉与洞察共用一个模型 */
export const chatModel = deepseek(config.modelId);
