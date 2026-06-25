import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash, randomBytes } from "node:crypto";
import { test } from "vitest";
import type { GameAsset } from "../src/providers/provider";
import { selectInvalidAssets, writeIntegrityIndex } from "../src/services/game-integrity";
import { normalizeBuild } from "../src/providers/provider";

const COUNT = 2000;

function generateAssets(count: number): GameAsset[] {
  const assets: GameAsset[] = [];
  for (let i = 0; i < count; i += 1) {
    const block = String(i % 200).padStart(2, "0");
    const name = `GenshinImpact_Data/StreamingAssets/AssetBundles/blocks/${block}/${String(i).padStart(8, "0")}_${randomBytes(4).toString("hex")}`;
    const size = (i % 1000) * 1024 + 128;
    const md5 = createHash("md5").update(randomBytes(16)).digest("hex");
    assets.push({ name, size, md5, chunks: [] });
  }
  return assets;
}

function writeAssetFiles(root: string, assets: GameAsset[]): void {
  for (const asset of assets) {
    const normalized = asset.name.replaceAll("\\", "/");
    const target = join(root, normalized);
    mkdirSync(join(target, ".."), { recursive: true });
    writeFileSync(target, Buffer.alloc(asset.size));
  }
}

function writePkgVersion(root: string, assets: GameAsset[]): void {
  const lines = assets.map((a) => JSON.stringify({ remoteName: a.name, md5: a.md5 }));
  const content = lines.join("\n");
  for (const name of ["pkg_version", "Audio_Chinese_pkg_version", "Audio_English(US)_pkg_version", "Audio_Japanese_pkg_version", "Audio_Korean_pkg_version"]) {
    writeFileSync(join(root, name), content);
  }
}

test("基准：有 .mhg-integrity.json 索引的校验耗时", () => {
  const root = mkdtempSync(join(tmpdir(), "bench-index-"));
  const assets = generateAssets(COUNT);
  writeAssetFiles(root, assets);
  writePkgVersion(root, assets);
  const build = normalizeBuild({ version: "5.8.0", assets });
  writeIntegrityIndex(root, build);

  const start = performance.now();
  const invalid = selectInvalidAssets(root, assets);
  const elapsed = (performance.now() - start).toFixed(2);

  rmSync(root, { recursive: true, force: true });
  console.log(`\n[索引快速路径] ${COUNT} 个文件，无效 ${invalid.length} 个，耗时 ${elapsed}ms`);
});

test("基准：无索引仅靠 pkg_version 回退的校验耗时", () => {
  const root = mkdtempSync(join(tmpdir(), "bench-package-"));
  const assets = generateAssets(COUNT);
  writeAssetFiles(root, assets);
  writePkgVersion(root, assets);

  const start = performance.now();
  const invalid = selectInvalidAssets(root, assets);
  const elapsed = (performance.now() - start).toFixed(2);

  rmSync(root, { recursive: true, force: true });
  console.log(`\n[pkg_version回退] ${COUNT} 个文件，无效 ${invalid.length} 个，耗时 ${elapsed}ms`);
});

test("基准：有索引但文件被修改过的校验耗时", () => {
  const root = mkdtempSync(join(tmpdir(), "bench-modified-"));
  const assets = generateAssets(COUNT);
  writeAssetFiles(root, assets);
  writePkgVersion(root, assets);
  const build = normalizeBuild({ version: "5.8.0", assets });
  writeIntegrityIndex(root, build);

  for (let i = 0; i < 20; i += 1) {
    const asset = assets[i];
    if (!asset) continue;
    const target = join(root, asset.name.replaceAll("\\", "/"));
    writeFileSync(target, randomBytes(asset.size));
  }

  const start = performance.now();
  const invalid = selectInvalidAssets(root, assets);
  const elapsed = (performance.now() - start).toFixed(2);

  rmSync(root, { recursive: true, force: true });
  console.log(`\n[索引+部分修改] ${COUNT} 个文件，检测出无效 ${invalid.length} 个，耗时 ${elapsed}ms`);
});
