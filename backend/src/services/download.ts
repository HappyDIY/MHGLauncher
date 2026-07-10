import { existsSync, renameSync, rmSync } from "node:fs";
import { AppError } from "../core/errors";
import type { PackageSegment } from "../providers/provider";
import { streamDownload } from "./download-transfer";
import { hashFileSync } from "./file-hash";

export class DownloadControl {
  private paused = false; private cancelled = false; private waiters: (() => void)[] = []; private readonly controller = new AbortController();
  get signal(): AbortSignal { return this.controller.signal; }
  pause(): void { this.paused = true; }
  resume(): void { this.paused = false; this.release(); }
  cancel(): void { this.cancelled = true; this.controller.abort(); this.release(); }
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
  const partial = `${destination}.part`;
  await streamDownload(segment.url, partial, segment.size, segment.filename, control, progress);
  if (!existsSync(partial)) throw new AppError("download_size_mismatch", `${segment.filename} 下载大小不一致`);
  if (hash(partial, "md5") !== segment.md5.toLowerCase()) { rmSync(partial); throw new AppError("download_hash_mismatch", `${segment.filename} 校验失败`); }
  renameSync(partial, destination); return destination;
}

export function hash(path: string, algorithm: "md5" | "sha256"): string {
  return hashFileSync(path, algorithm);
}
