import { Hono } from 'hono';
import { z } from 'zod';
import { createThread, deleteThread, getThread, listThreads, updateThread } from '../db/threads.js';
import { notFound, parse, readJson } from '../http.js';

export const threadRoutes = new Hono();

const createSchema = z.object({ title: z.string().optional() });
const patchSchema = z.object({
  title: z.string().min(1).optional(),
  contactName: z.string().optional(),
});

threadRoutes.post('/threads', async (c) => {
  const body = parse(createSchema, await readJson(c));
  const threadId = await createThread(body.title ?? '');
  return c.json({ threadId });
});

threadRoutes.get('/threads', async (c) => c.json(await listThreads()));

threadRoutes.patch('/threads/:id', async (c) => {
  const id = c.req.param('id');
  const body = parse(patchSchema, await readJson(c));
  const thread = await getThread(id);
  if (!thread) throw notFound('会话不存在');
  await updateThread(id, body);
  return c.json({ ok: true });
});

threadRoutes.delete('/threads/:id', async (c) => {
  await deleteThread(c.req.param('id'));
  return c.json({ ok: true });
});
