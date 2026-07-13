import { mkdtempSync, rmSync, writeFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import type { GameAsset } from "../src/providers/provider";
import { selectInvalidAssets, writeIntegrityIndex } from "../src/services/game-integrity";
import { normalizeBuild } from "../src/providers/provider";

const asset = (name: string, content: string): GameAsset => ({
  name, size: Buffer.byteLength(content), md5: "900150983cd24fb0d6963f7d28e17f72", chunks: [],
});

test("已验证索引使用元数据快速校验并发现变化", () => {
  const root = mkdtempSync(join(tmpdir(), "integrity-")), value = asset("data.bin", "abc");
  writeFileSync(join(root, "pkg_version"), JSON.stringify({ remoteName: value.name, md5: value.md5 }));
  writeFileSync(join(root, value.name), "abc");
  writeIntegrityIndex(root, normalizeBuild({ version: "1", assets: [value] }));
  expect(selectInvalidAssets(root, [value])).toEqual([]);
  writeFileSync(join(root, value.name), "xyz");
  expect(selectInvalidAssets(root, [value])).toEqual([value]);
});

test("官方清单快速路径仍检查文件存在与大小", () => {
  const root = mkdtempSync(join(tmpdir(), "integrity-package-")), value = asset("data.bin", "abc");
  writeFileSync(join(root, "pkg_version"), JSON.stringify({ remoteName: value.name, md5: value.md5 }));
  writeFileSync(join(root, value.name), "abc");
  expect(selectInvalidAssets(root, [value])).toEqual([]);
  rmSync(join(root, value.name));
  expect(selectInvalidAssets(root, [value])).toEqual([value]);
});

test("显式校验读取内容并拒绝同尺寸同时间损坏", () => {
  const root = mkdtempSync(join(tmpdir(), "integrity-strict-")), value = asset("data.bin", "abc"), path = join(root, value.name);
  const fixed = new Date("2026-01-01T00:00:00Z");
  writeFileSync(path, "abc"); utimesSync(path, fixed, fixed);
  writeIntegrityIndex(root, normalizeBuild({ version: "1", assets: [value] }));
  writeFileSync(path, "xyz"); utimesSync(path, fixed, fixed);
  expect(selectInvalidAssets(root, [value])).toEqual([]);
  expect(selectInvalidAssets(root, [value], true)).toEqual([value]);
});
