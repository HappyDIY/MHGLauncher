import { closeSync, openSync, rmSync, statSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import { preallocateFileDescriptor } from "../src/services/file-allocation";
import { readPredownloadStatus, writePredownloadStatus, clearPredownloadStatus } from "../src/services/predownload-status";

const roots: string[] = [];
const root = (): string => { const dir = mkdtempSync(join(tmpdir(), "alloc-")); roots.push(dir); return dir; };
afterEach(() => { for (const dir of roots.splice(0)) rmSync(dir, { recursive: true, force: true }); });

test("ftruncate 预分配文件到指定大小", () => {
  const path = join(root(), "test.bin");
  const fd = openSync(path, "w");
  preallocateFileDescriptor(fd, 1024 * 1024);
  closeSync(fd);
  expect(statSync(path).size).toBe(1024 * 1024);
});

test("预下载状态读写清除", () => {
  const dir = root();
  expect(readPredownloadStatus(dir)).toBe(null);
  writePredownloadStatus(dir, { tag: "5.6.0", finished: false, total_chunks: 100 });
  const status = readPredownloadStatus(dir);
  expect(status?.tag).toBe("5.6.0");
  expect(status?.finished).toBe(false);
  expect(status?.total_chunks).toBe(100);
  clearPredownloadStatus(dir);
  expect(readPredownloadStatus(dir)).toBe(null);
});