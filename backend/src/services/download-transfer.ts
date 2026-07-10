import { closeSync, existsSync, mkdirSync, openSync, rmSync, statSync, writeSync } from "node:fs";
import { dirname } from "node:path";
import { AppError } from "../core/errors";
import type { DownloadControl } from "./download";
import type { TokenBucketRateLimiter } from "./rate-limiter";

const retryLimit = 5;

export async function streamDownload(
  url: string, partial: string, expectedSize: number, label: string, control: DownloadControl,
  progress: (delta: number) => void, report: (done: number) => void = () => undefined,
  rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(dirname(partial), { recursive: true });
  let offset = existsSync(partial) ? statSync(partial).size : 0;
  if (offset > expectedSize) { rmSync(partial); offset = 0; }
  if (offset) { progress(offset); report(offset); }
  let failures = 0;
  while (offset < expectedSize) {
    await control.checkpoint();
    try {
      const response = await fetch(url, { headers: offset ? { Range: `bytes=${offset}-` } : {}, signal: control.signal });
      if (offset && response.status !== 206) {
        progress(-offset); offset = 0; report(0); rmSync(partial, { force: true });
        continue;
      }
      if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
      const reader = response.body.getReader(), descriptor = openSync(partial, offset ? "a" : "w");
      try {
        while (offset < expectedSize) {
          await control.checkpoint();
          const value = await reader.read();
          if (value.done) break;
          if (rateLimiter) await acquireBytes(rateLimiter, value.value.length, control);
          writeSync(descriptor, value.value); offset += value.value.length;
          progress(value.value.length); report(offset);
          if (offset > expectedSize) throw new Error("响应大小超出清单");
        }
      } finally { closeSync(descriptor); }
      if (offset < expectedSize) throw new Error("连接提前结束");
      failures = 0;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") throw error;
      failures += 1;
      if (failures > retryLimit) {
        const detail = error instanceof Error ? error.message : "未知错误";
        throw new AppError("download_failed", `${label} 下载失败，自动重试 ${retryLimit} 次后仍未恢复：${detail}`, 502);
      }
      await waitForRetry(control, failures);
      offset = existsSync(partial) ? statSync(partial).size : 0;
      if (offset > expectedSize) {
        progress(-offset); offset = 0; report(0); rmSync(partial, { force: true });
      }
    }
  }
}

async function acquireBytes(limiter: TokenBucketRateLimiter, bytes: number, control: DownloadControl): Promise<void> {
  let remaining = bytes;
  while (remaining > 0) {
    await control.checkpoint();
    const { acquired, retryAfterMs } = limiter.tryAcquire(remaining);
    remaining -= acquired;
    if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, Math.max(retryAfterMs, 1)));
  }
}

async function waitForRetry(control: DownloadControl, attempt: number): Promise<void> {
  await control.checkpoint();
  const delay = process.env.NODE_ENV === "test" ? 1 : Math.min(500 * 2 ** (attempt - 1), 8_000);
  await new Promise((resolve) => setTimeout(resolve, delay));
}
