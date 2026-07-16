import { closeSync, existsSync, mkdirSync, openSync, rmSync, statSync, writeSync } from "node:fs";
import { dirname } from "node:path";
import { AppError } from "../core/errors";
import type { DownloadControl } from "./download";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import { localStorageError } from "./storage-error";

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
      const response = await fetchHeaders(url, offset, control);
      if (offset && (response.status !== 206 || !validRange(response.headers.get("content-range"), offset, expectedSize))) {
        progress(-offset); offset = 0; report(0); rmSync(partial, { force: true });
        continue;
      }
      if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
      const remaining = expectedSize - offset, length = Number(response.headers.get("content-length") ?? remaining);
      if (Number.isFinite(length) && length > remaining) throw new Error("响应大小超出清单");
      const reader = response.body.getReader(), descriptor = openFile(partial, offset ? "a" : "w");
      try {
        while (offset < expectedSize) {
          await control.checkpoint();
          const value = await readWithStall(reader, label);
          if (value.done) break;
          if (rateLimiter) await acquireBytes(rateLimiter, value.value.length, control);
          writeFile(descriptor, value.value); offset += value.value.length;
          progress(value.value.length); report(offset);
          if (offset > expectedSize) throw new Error("响应大小超出清单");
        }
      } finally { closeSync(descriptor); if (offset >= expectedSize) void reader.cancel(); }
      if (offset < expectedSize) throw new Error("连接提前结束");
      failures = 0;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") throw error;
      if (error instanceof AppError && error.code === "storage_write_failed") throw error;
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

function validRange(value: string | null, offset: number, expectedSize: number): boolean {
  const match = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(value ?? "");
  return match !== null && Number(match[1]) === offset && Number(match[2]) < expectedSize && Number(match[3]) === expectedSize;
}

function stallTimeout(): number {
  const configured = Number(process.env.MHG_DOWNLOAD_STALL_TIMEOUT_MS ?? 30_000);
  return Number.isFinite(configured) ? Math.max(50, configured) : 30_000;
}

async function fetchHeaders(url: string, offset: number, control: DownloadControl): Promise<Response> {
  const stalled = new AbortController();
  const timer = setTimeout(() => stalled.abort(), stallTimeout());
  try {
    return await fetch(url, {
      headers: offset ? { Range: `bytes=${offset}-` } : {},
      signal: AbortSignal.any([control.signal, stalled.signal]),
    });
  } catch (error) {
    if (stalled.signal.aborted) throw new AppError("download_stalled", "下载连接长时间无响应", 504);
    throw error;
  } finally { clearTimeout(timer); }
}

async function readWithStall(reader: ReadableStreamDefaultReader<Uint8Array>, label: string): Promise<ReadableStreamReadResult<Uint8Array>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      reader.read(),
      new Promise<never>((_resolve, reject) => { timer = setTimeout(() => reject(new AppError("download_stalled", `${label} 下载连接长时间无数据`, 504)), stallTimeout()); }),
    ]);
  } catch (error) { void reader.cancel(); throw error; }
  finally { if (timer) clearTimeout(timer); }
}

function openFile(path: string, flags: "a" | "w"): number {
  try { return openSync(path, flags); } catch (error) { throw localStorageError(error); }
}

function writeFile(descriptor: number, value: Uint8Array): void {
  try { writeSync(descriptor, value); } catch (error) { throw localStorageError(error); }
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
