import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs";
import { join, resolve } from "node:path";
import type { GameState } from "../core/models";
import type { GameBuild } from "../providers/provider";
import { recoverActivation } from "./installer";
import { managedPath } from "./managed-file";
import { operationChunks } from "./game-build";

export function detectGame(input: string): { path: string; version: string } | null {
  for (const candidate of [resolve(input), join(resolve(input), "Genshin Impact Game")]) {
    try {
      const path = existsSync(candidate) ? realpathSync(candidate) : candidate;
      recoverActivation(path);
      const executable = managedPath(path, "YuanShen.exe");
      if (!existsSync(executable) || !lstatSync(executable).isFile()) continue;
      const config = managedPath(path, "config.ini");
      const official = existsSync(config) ? readFileSync(config, "utf8").match(/^game_version\s*=\s*(.+)$/m)?.[1]?.trim() : "";
      if (official) return { path, version: official };
      const marker = managedPath(path, ".mhg-version");
      if (existsSync(marker)) { const version = readFileSync(marker, "utf8").trim(); if (version) return { path, version }; }
    } catch { continue; }
  }
  return null;
}

export function audioLanguages(path: string): string[] {
  const files: Record<string, string> = {
    "zh-cn": "Audio_Chinese_pkg_version", "en-us": "Audio_English(US)_pkg_version",
    "ja-jp": "Audio_Japanese_pkg_version", "ko-kr": "Audio_Korean_pkg_version",
  };
  const selected = Object.entries(files).filter(([, name]) => existsSync(join(path, name))).map(([language]) => language);
  return selected.length ? selected : ["zh-cn"];
}

export function gameBuildSize(build: GameBuild): number {
  const patches = new Map(build.patch_assets.map(({ patch }) => [patch.id, patch.file_size]));
  const chunks = new Map(build.assets.flatMap(operationChunks).map((chunk) => [chunk.name, chunk.size]));
  return build.pending_bytes + build.segments.reduce((total, value) => total + value.size, 0)
    + [...chunks.values()].reduce((total, value) => total + value, 0)
    + [...patches.values()].reduce((total, value) => total + value, 0);
}

export function gameStorageSize(build: GameBuild, predownload = false): number {
  const download = gameBuildSize(build);
  if (predownload) return download;
  const outputs = new Map<string, number>();
  for (const asset of build.assets) outputs.set(asset.name.toLowerCase(), asset.size);
  for (const asset of build.patch_assets) outputs.set(asset.name.toLowerCase(), asset.size);
  if (!outputs.size) return download;
  return [...outputs.values()].reduce((total, value) => total + value, 0);
}

export function gameStateOutput(
  path: string, installed: string, build: GameBuild, status: GameState["status"],
  predownload?: { version: string | null; finished: boolean },
): GameState {
  return { install_path: path, installed_version: installed, available_version: build.version, status,
    update_kind: build.kind, download_bytes: gameBuildSize(build), predownload_version: predownload?.version ?? null,
    predownload_finished: predownload?.finished ?? false };
}
