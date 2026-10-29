import { Hono } from 'hono';
import { resetDemo, seedDemo } from '../services/demo-seed.js';

export const demoRoutes = new Hono();

demoRoutes.post('/demo/seed', async (c) => c.json(await seedDemo()));

demoRoutes.post('/demo/reset', async (c) => {
  await resetDemo();
  return c.json({ ok: true });
});
