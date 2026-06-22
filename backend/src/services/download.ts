import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync } from "node:fs";
import { dirname } from "node:path";
import { AppError } from "../core/errors";
import type { PackageSegment } from "../providers/provider";

export class DownloadControl {
  private paused = false; private cancelled = false; private waiters: (() => void)[] = [];
  pause(): void { this.paused = true; }
  resume(): void { this.paused = false; this.release(); }
  cancel(): void { this.cancelled = true; this.release(); }
  async checkpoint(): Promise<void> {
    if (this.paused) await new Promise<void>((resolve) => this.waiters.push(resolve));
    if (this.cancelled) throw new DOMException("任务已取消", "AbortError");
  }
  private release(): void { for (const resolve of this.waiters.splice(0)) resolve(); }
}

export async function download(
  segment: PackageSegment, destination: string, control: DownloadControl,
  progress: (bytes: number) => void,
): Promise<string> {
  mkdirSync(dirname(destination), { recursive: true }); const partial = `${destination}.part`;
  let offset = existsSync(partial) ? statSync(partial).size : 0;
  if (offset > segment.size) { rmSync(partial); offset = 0; }
  const response = await fetch(segment.url, { headers: offset ? { Range: `bytes=${offset}-` } : {} });
  if (!response.ok) throw new AppError("download_failed", `${segment.filename} 下载失败`, 502);
  if (offset && response.status !== 206) { rmSync(partial, { force: true }); return download(segment, destination, control, progress); }
  const reader = response.body?.getReader(); if (!reader) throw new AppError("download_failed", `${segment.filename} 响应为空`, 502);
  while (true) {
    const value = await reader.read(); if (value.done) break; await control.checkpoint();
    appendFileSync(partial, value.value); offset += value.value.length; progress(value.value.length);
  }
  if (offset !== segment.size) throw new AppError("download_size_mismatch", `${segment.filename} 下载大小不一致`);
  if (hash(partial, "md5") !== segment.md5.toLowerCase()) { rmSync(partial); throw new AppError("download_hash_mismatch", `${segment.filename} 校验失败`); }
  renameSync(partial, destination); return destination;
}

export function hash(path: string, algorithm: "md5" | "sha256"): string {
  return createHash(algorithm).update(readFileSync(path)).digest("hex");
}
