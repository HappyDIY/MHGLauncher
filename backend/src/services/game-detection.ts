import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import type { GameState } from "../core/models";
import type { GameBuild } from "../providers/provider";
import { recoverActivation } from "./installer";

export function detectGame(input: string): { path: string; version: string } | null {
  for (const path of [resolve(input), join(resolve(input), "Genshin Impact Game")]) {
    recoverActivation(path);
    if (!existsSync(join(path, "YuanShen.exe"))) continue;
    const config = join(path, "config.ini");
    const official = existsSync(config) ? readFileSync(config, "utf8").match(/^game_version\s*=\s*(.+)$/m)?.[1]?.trim() : "";
    if (official) return { path, version: official };
    const marker = join(path, ".mhg-version");
    if (existsSync(marker)) { const version = readFileSync(marker, "utf8").trim(); if (version) return { path, version }; }
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
  return build.pending_bytes + build.segments.reduce((total, value) => total + value.size, 0)
    + build.assets.flatMap((value) => value.chunks).reduce((total, value) => total + value.size, 0)
    + [...patches.values()].reduce((total, value) => total + value, 0);
}

export function gameStateOutput(
  path: string, installed: string, build: GameBuild, status: GameState["status"],
  predownload?: { version: string | null; finished: boolean },
): GameState {
  return { install_path: path, installed_version: installed, available_version: build.version, status,
    update_kind: build.kind, download_bytes: gameBuildSize(build), predownload_version: predownload?.version ?? null,
    predownload_finished: predownload?.finished ?? false };
}
