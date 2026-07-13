import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import xxhash from "xxhash-wasm";
import type { GamePatchAsset } from "../src/providers/provider";
import { DownloadControl } from "../src/services/download";
import { installPatches } from "../src/services/patch-install";

const originalTool = process.env.MHG_HPATCHZ;
afterEach(() => { process.env.MHG_HPATCHZ = originalTool; });

test("补丁结果校验失败不覆盖目标", async () => {
  const root = mkdtempSync(join(tmpdir(), "patch-")), staging = join(root, "game"), cache = join(root, "cache");
  const patch = Buffer.from("xxxxnewyyyy"), asset = await directAsset(patch, "target.bin", "0".repeat(32));
  mkdirSync(staging); mkdirSync(cache);
  writeFileSync(join(cache, asset.patch.id), patch, { flag: "wx" }); writeFileSync(join(staging, "target.bin"), "old", { flag: "wx" });
  await expect(installPatches([asset], staging, cache, new DownloadControl(), () => undefined, () => undefined)).rejects.toThrow("校验失败");
  expect(readFileSync(join(staging, "target.bin"), "utf8")).toBe("old");
});

test("重命名补丁使用 original_name 作为源文件", async () => {
  const root = mkdtempSync(join(tmpdir(), "patch-")), staging = join(root, "game"), cache = join(root, "cache"), tool = join(root, "hpatchz");
  const patch = Buffer.from("p"), id = await patchId(patch), content = "source-data";
  mkdirSync(staging); mkdirSync(cache);
  writeFileSync(join(cache, id), patch, { flag: "wx" }); writeFileSync(join(staging, "old.bin"), content, { flag: "wx" });
  writeFileSync(tool, "#!/bin/sh\ncp \"$1\" \"$3\"\n"); chmodSync(tool, 0o755); process.env.MHG_HPATCHZ = tool;
  const asset: GamePatchAsset = { name: "renamed.bin", size: content.length, md5: md5(content),
    patch: { id, file_size: 1, start: 0, length: 1, original_name: "old.bin", url: "https://unused" } };
  await installPatches([asset], staging, cache, new DownloadControl(), () => undefined, () => undefined);
  expect(readFileSync(join(staging, "renamed.bin"), "utf8")).toBe(content);
});

async function directAsset(patch: Buffer, name: string, expected: string): Promise<GamePatchAsset> {
  return { name, size: 3, md5: expected, patch: {
    id: await patchId(patch), file_size: patch.length, start: 4, length: 3, original_name: "", url: "https://unused",
  } };
}

async function patchId(value: Buffer): Promise<string> { return `${(await xxhash()).h64Raw(value).toString(16).padStart(16, "0")}_patch`; }
function md5(value: string): string { return createHash("md5").update(value).digest("hex"); }
