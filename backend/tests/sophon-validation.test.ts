import { expect, test } from "vitest";
import { validateSophonAssets, validateSophonPatches, validateSophonPaths } from "../src/providers/sophon-validation";

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
