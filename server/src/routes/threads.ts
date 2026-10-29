import { Router } from 'express';
import { z } from 'zod';
import { createThread, deleteThread, getThread, listThreads, updateThread } from '../db/threads.js';

export const threadsRouter = Router();

const createSchema = z.object({ title: z.string().optional() });
const patchSchema = z.object({ title: z.string().min(1).optional(), contactName: z.string().optional() });

threadsRouter.post('/threads', async (req, res, next) => {
  try {
    const body = createSchema.parse(req.body ?? {});
    const threadId = await createThread(body.title ?? '');
    res.json({ threadId });
  } catch (error) {
    next(error);
  }
});

threadsRouter.get('/threads', async (_req, res, next) => {
  try {
    res.json(await listThreads());
  } catch (error) {
    next(error);
  }
});

threadsRouter.patch('/threads/:id', async (req, res, next) => {
  try {
    const body = patchSchema.parse(req.body ?? {});
    const thread = await getThread(req.params.id);
    if (!thread) {
      res.status(404).json({ error: '会话不存在' });
      return;
    }
    await updateThread(req.params.id, body);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

threadsRouter.delete('/threads/:id', async (req, res, next) => {
  try {
    await deleteThread(req.params.id);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});
