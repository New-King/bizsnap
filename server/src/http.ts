import type { Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { z } from 'zod';

/** 空 body 也当 `{}`，让 zod 的默认值/可选字段说话 */
export async function readJson(c: Context): Promise<unknown> {
  try {
    return await c.req.json();
  } catch {
    return {};
  }
}

/** zod 校验失败统一转 400，错误文案直接取第一条 issue */
export function parse<T extends z.ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const issue = result.error.issues[0];
    const field = issue?.path.join('.') || 'body';
    throw new HTTPException(400, { message: `${field}：${issue?.message ?? '参数不合法'}` });
  }
  return result.data;
}

export function notFound(message: string): HTTPException {
  return new HTTPException(404, { message });
}
