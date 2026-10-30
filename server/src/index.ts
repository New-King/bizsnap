import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import { HTTPException } from 'hono/http-exception';
import { config } from './config.js';
import { ensureSchema } from './db/schema.js';
import { confirmRoutes } from './routes/confirm.js';
import { demoRoutes } from './routes/demo.js';
import { messageRoutes } from './routes/messages.js';
import { threadRoutes } from './routes/threads.js';

const app = new Hono();

app.use('*', cors());

// 每个请求留一行日志：真机连不上时，先看有没有请求打进来
app.use('/api/*', async (c, next) => {
  const started = Date.now();
  await next();
  console.log(
    `[bizsnap] ${c.req.method} ${c.req.path} → ${c.res.status} ${Date.now() - started}ms`,
  );
});

app.use(
  '/api/*',
  bodyLimit({
    maxSize: 12 * 1024 * 1024,
    onError: (c) => c.json({ error: '请求体过大（上限 12MB），截图请先压缩' }, 413),
  }),
);

app.get('/api/health', (c) =>
  c.json({ ok: true, model: config.modelId, time: new Date().toISOString() }),
);

app.route('/api', demoRoutes);
app.route('/api', threadRoutes);
app.route('/api', messageRoutes);
app.route('/api', confirmRoutes);

app.notFound((c) => c.json({ error: '接口不存在' }, 404));

app.onError((error, c) => {
  const status = (error instanceof HTTPException
    ? error.status
    : ((error as { status?: number }).status ?? 500)) as ContentfulStatusCode;

  if (status >= 500) {
    console.error('[bizsnap] 请求失败：', error);
  }
  return c.json({ error: error.message || '服务端错误' }, status);
});

async function main(): Promise<void> {
  await ensureSchema();
  // 提前加载 agent，把配置错误暴露在启动阶段
  await import('./mastra/index.js');

  serve({ fetch: app.fetch, port: config.port, hostname: config.host }, () => {
    console.log(`[bizsnap] 服务已启动 http://${config.host}:${config.port}`);
    console.log(`[bizsnap] 数据库 ${config.dbFile}`);
  });
}

main().catch((error) => {
  console.error('[bizsnap] 启动失败：', error);
  process.exit(1);
});
