import { expect, test } from "vitest";
import { validateSophonAssets, validateSophonPatches, validateSophonPaths } from "../src/providers/sophon-validation";
import { hasCompletePatchStats, selectPatchOrRemote, selectUpdateBuild } from "../src/providers/build-selection";
import { normalizeBuild } from "../src/providers/provider";

test("拒绝越界或非安全整数的 Sophon 分块", () => {
  expect(() => validateSophonAssets([{ name: "game.bin", size: 4, md5: "0".repeat(32), chunks: [{
    name: "0123456789abcdef_chunk", decompressed_md5: "0".repeat(32), offset: 3,
    size: 1, decompressed_size: 2, url: "https://fixture/chunk",
  }] }])).toThrow("无效字段");
});

test("拒绝同名但元数据不一致的共享分块", () => {
  const chunk = { name: "0123456789abcdef_chunk", decompressed_md5: "0".repeat(32), offset: 0,
    size: 1, decompressed_size: 1, url: "https://fixture/one" };
  expect(() => validateSophonAssets([
    { name: "one.bin", size: 1, md5: "0".repeat(32), chunks: [chunk] },
    { name: "two.bin", size: 2, md5: "0".repeat(32), chunks: [{ ...chunk, decompressed_size: 2 }] },
  ])).toThrow("无效字段");
});

test("拒绝补丁越界和退役文件路径穿越", () => {
  expect(() => validateSophonPatches([{ name: "game.bin", size: 1, md5: "0".repeat(32), patch: {
    id: "0123456789abcdef_patch", file_size: 1, start: 1, length: 1, original_name: "", url: "https://fixture",
  } }])).toThrow("无效字段");
  expect(() => validateSophonPaths(["../victim"])).toThrow("无效字段");
});

test("补丁选择要求完整版本统计和一致的目标版本", async () => {
  const remote = normalizeBuild({ version: "6.8.0", assets: [] });
  const mismatch = normalizeBuild({ version: "6.9.0", kind: "version_diff" });
  expect(hasCompletePatchStats([{ stats: { "6.7.0": {} } }], "6.7.0")).toBe(true);
  expect(hasCompletePatchStats([{ stats: {} }], "6.7.0")).toBe(false);
  expect(await selectPatchOrRemote(remote, async () => mismatch)).toBe(remote);
});

test("补丁不可用时退回完整清单分块差分", async () => {
  const local = normalizeBuild({ version: "6.7.0", assets: [{ name: "game.bin", size: 1, md5: "0".repeat(32), chunks: [] }] });
  const remote = normalizeBuild({ version: "6.8.0", assets: [{ name: "game.bin", size: 1, md5: "1".repeat(32), chunks: [] }] });
  const selected = await selectUpdateBuild(remote, async () => local, async () => { throw new Error("missing"); });
  expect(selected).toMatchObject({ version: "6.8.0", kind: "version_diff_chunks", repair_assets: remote.assets });
});
