import { createHash } from "node:crypto";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import type { GameAsset, GameBuild } from "../providers/provider";

export function prepareBuild(build: GameBuild, path: string, installed: string): GameBuild {
  if (!path || installed !== build.version) return build;
  const pending = ["data_versions_remote", "res_versions_remote", "silence_data_versions_remote"]
    .reduce((total, name) => total + manifestSize(join(path, "YuanShen_Data/Persistent", name)), 0);
  if (pending) return { ...build, kind: "game_hotfix", pending_bytes: pending };
  if (!build.assets.length) return build;
  const hashes = localHashes(path), assets = build.assets.filter((asset) => localHash(asset, path, hashes) !== asset.md5.toLowerCase());
  return { ...build, assets, kind: "package_repair" };
}

export function removeRetired(staging: string, build: GameBuild): void {
  const path = join(staging, ".mhg-assets.json"); if (!existsSync(path)) return;
  const current = new Set(build.assets.map(({ name }) => name));
  for (const name of JSON.parse(readFileSync(path, "utf8")) as string[]) if (!current.has(name)) removeSafe(staging, name);
}

export function removeSafe(root: string, name: string): void {
  const target = resolve(root, name.replaceAll("\\", "/")), child = relative(resolve(root), target);
  if (!isAbsolute(child) && !child.startsWith("..")) rmSync(target, { force: true });
}

function manifestSize(path: string): number {
  if (!existsSync(path)) return 0; let total = 0;
  for (const line of readFileSync(path, "utf8").split("\n")) { try { total += Math.max(Number((JSON.parse(line) as { fileSize?: number }).fileSize ?? 0), 0); } catch { /* 忽略损坏的单行 */ } }
  return total;
}

function localHashes(root: string): Map<string, string> {
  const result = new Map<string, string>();
  for (const name of ["pkg_version", "Audio_Chinese_pkg_version"]) {
    const path = join(root, name); if (!existsSync(path)) continue;
    for (const line of readFileSync(path, "utf8").split("\n")) { try { const value = JSON.parse(line) as { remoteName: string; md5: string }; result.set(value.remoteName.replaceAll("\\", "/"), value.md5.toLowerCase()); } catch { /* 忽略损坏的单行 */ } }
  }
  return result;
}

function localHash(asset: GameAsset, root: string, values: Map<string, string>): string {
  const name = asset.name.replaceAll("\\", "/"), known = values.get(name); if (known) return known;
  const path = join(root, name); return existsSync(path) ? createHash("md5").update(readFileSync(path)).digest("hex") : "";
}
