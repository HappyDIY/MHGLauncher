import { existsSync, readFileSync, rmSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import type { GameBuild } from "../providers/provider";
import { selectInvalidAssets } from "./game-integrity";

export function prepareBuild(build: GameBuild, path: string, installed: string): GameBuild {
  if (!path || installed !== build.version) return build;
  const pending = ["data_versions_remote", "res_versions_remote", "silence_data_versions_remote"]
    .reduce((total, name) => total + manifestSize(join(path, "YuanShen_Data/Persistent", name)), 0);
  if (pending) return { ...build, kind: "game_hotfix", pending_bytes: pending };
  if (!build.assets.length) return build;
  const assets = selectInvalidAssets(path, build.assets);
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
