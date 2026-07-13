import { existsSync, readFileSync, rmSync } from "node:fs";
import { basename, join, normalize } from "node:path";
import type { GameBuild } from "../providers/provider";
import { selectInvalidAssets } from "./game-integrity";
import { containedPath } from "../core/safe-path";

export function prepareBuild(build: GameBuild, path: string, installed: string, strictVerify = false): GameBuild {
  const protectedBuild = withoutProtectedAssets(build);
  if (!path || installed !== protectedBuild.version) return protectedBuild;
  if (!protectedBuild.assets.length) return protectedBuild;
  const assets = selectInvalidAssets(path, protectedBuild.assets, strictVerify);
  return { ...protectedBuild, assets, kind: "package_repair" };
}

export function removeRetired(staging: string, build: GameBuild): void {
  const path = join(staging, ".mhg-assets.json"); if (!existsSync(path)) return;
  const current = new Set(build.assets.map(({ name }) => name));
  for (const name of JSON.parse(readFileSync(path, "utf8")) as string[]) if (!current.has(name)) removeSafe(staging, name);
}

export function removeSafe(root: string, name: string): void {
  if (isProtectedAsset(name)) return;
  rmSync(containedPath(root, name), { force: true });
}

function withoutProtectedAssets(build: GameBuild): GameBuild {
  return {
    ...build,
    assets: build.assets.filter((asset) => !isProtectedAsset(asset.name)),
    patch_assets: build.patch_assets.filter((asset) => !isProtectedAsset(asset.name)),
    deprecated_files: build.deprecated_files.filter((name) => !isProtectedAsset(name)),
  };
}

function isProtectedAsset(name: string): boolean {
  // mhypbase.dll 由启动器运行时提供，不能被官方资源更新替换。
  const canonical = normalize(name.replaceAll("\\", "/"));
  return basename(canonical).toLowerCase() === "mhypbase.dll";
}
