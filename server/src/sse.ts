import { withSseHeartbeat } from '@mastra/ai-sdk';

export type SseSend = (payload: Record<string, unknown>) => void;

/** 心跳间隔：中间层通常 60s 掐空闲连接，15s 留足余量 */
const HEARTBEAT_MS = 15_000;

/**
 * 一帧 = 一行 `data: <json>`。
 * 不用 SSE 的 `event:` 名：客户端（Swift）只按行读、只认 `data:` 前缀，解析器十几行就够。
 * 心跳交给 Mastra 的 `withSseHeartbeat`，它只在两帧之间插 `: heartbeat` 注释，不打断帧。
 */
export function sseResponse(
  signal: AbortSignal,
  handler: (send: SseSend) => Promise<void>,
): Response {
  const encoder = new TextEncoder();

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      let closed = false;
      const send: SseSend = (payload) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
        } catch {
          closed = true;
        }
      };

      try {
        await handler(send);
      } catch (error) {
        if (!signal.aborted) {
          console.error('[bizsnap] 流式响应失败：', error);
          send({ type: 'error', error: error instanceof Error ? error.message : '服务端错误' });
        }
      } finally {
        closed = true;
        try {
          controller.close();
        } catch {
          // 客户端已经断开
        }
      }
    },
    cancel() {
      // 客户端断开：signal 会同时 abort，上游循环据此退出
    },
  });

  const response = new Response(body, {
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    },
  });

  return withSseHeartbeat(response, HEARTBEAT_MS);
}
