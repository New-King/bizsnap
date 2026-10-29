import { Router } from 'express';
import { z } from 'zod';
import { markCardsConfirmed } from '../db/threads.js';
import { confirmCards } from '../services/confirm.js';
import type { CardDraft } from '../types.js';

export const confirmRouter = Router();

const cardSchema = z.object({
  id: z.string(),
  kind: z.enum(['create_contact', 'update_contact', 'create_meeting']),
  reason: z.string().optional(),
  payload: z.record(z.string(), z.unknown()),
});

const confirmSchema = z.object({ cards: z.array(cardSchema).min(1) });

confirmRouter.post('/threads/:id/confirm', async (req, res, next) => {
  try {
    const body = confirmSchema.parse(req.body ?? {});
    const result = await confirmCards(req.params.id, body.cards as unknown as CardDraft[]);

    const done = result.written.filter((item) => item.ok).map((item) => item.cardId);
    await markCardsConfirmed(req.params.id, done);

    res.json(result);
  } catch (error) {
    next(error);
  }
});
