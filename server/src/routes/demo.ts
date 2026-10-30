import { Hono } from 'hono';
import { resetDemo } from '../services/demo-seed.js';

export const demoRoutes = new Hono();

demoRoutes.post('/demo/reset', async (c) => {
  const summary = await resetDemo();
  return c.json({ ok: true, ...summary });
});
