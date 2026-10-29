import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';
import { config } from './config.js';
import { ensureSchema } from './db/schema.js';
import { confirmRouter } from './routes/confirm.js';
import { demoRouter } from './routes/demo.js';
import { messagesRouter } from './routes/messages.js';
import { threadsRouter } from './routes/threads.js';

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, model: config.modelId, time: new Date().toISOString() });
});

app.use('/api', demoRouter);
app.use('/api', threadsRouter);
app.use('/api', messagesRouter);
app.use('/api', confirmRouter);

app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
  const err = error as { status?: number; message?: string; issues?: unknown };
  const status = err.status ?? 500;
  if (status >= 500) {
    console.error('[bizsnap] 请求失败：', error);
  }
  res.status(status).json({
    error: err.message ?? '服务端错误',
    issues: err.issues,
  });
});

async function main(): Promise<void> {
  await ensureSchema();
  // 提前加载 agent，把配置错误暴露在启动阶段
  await import('./mastra/index.js');
  app.listen(config.port, () => {
    console.log(`[bizsnap] 服务已启动 http://127.0.0.1:${config.port}`);
    console.log(`[bizsnap] 数据库 ${config.dbFile}`);
  });
}

main().catch((error) => {
  console.error('[bizsnap] 启动失败：', error);
  process.exit(1);
});
