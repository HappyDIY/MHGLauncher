import { expect, test } from "vitest";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { diskSpaceInfo } from "../src/services/disk-space";

test("磁盘空间检查返回可用空间", () => {
  const info = diskSpaceInfo(tmpdir(), 1024);
  expect(info.available).toBeGreaterThan(0);
  expect(info.required).toBe(1024 + 1024 * 1024 * 1024);
  expect(info.sufficient).toBe(true);
});

test("安装目录尚未创建时检查所在磁盘", () => {
  const path = join(tmpdir(), `mhg-space-${randomUUID()}`, "game");
  const info = diskSpaceInfo(path, 1024);
  expect(info.available).toBeGreaterThan(0);
});

test("大字节数检查正确触发空间不足", () => {
  const info = diskSpaceInfo(tmpdir(), Number.MAX_SAFE_INTEGER);
  expect(info.sufficient).toBe(false);
  expect(info.required).toBeGreaterThan(info.available);
});

test("已有下载量从需求中扣除", () => {
  const info = diskSpaceInfo(tmpdir(), 2 * 1024, 1024);
  expect(info.required).toBe(1024 + 1024 * 1024 * 1024);
});
