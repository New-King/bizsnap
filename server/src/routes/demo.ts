import { Router } from 'express';
import { resetDemo, seedDemo } from '../services/demo-seed.js';

export const demoRouter = Router();

demoRouter.post('/demo/seed', async (_req, res, next) => {
  try {
    res.json(await seedDemo());
  } catch (error) {
    next(error);
  }
});

demoRouter.post('/demo/reset', async (_req, res, next) => {
  try {
    await resetDemo();
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});
