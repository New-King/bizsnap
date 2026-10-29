import { Mastra } from '@mastra/core/mastra';
import { bizAgent } from './agent.js';
import { storage } from './storage.js';

export const mastra = new Mastra({
  agents: { bizsnap: bizAgent },
  storage,
});

export { bizAgent, storage };
