import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import { hash } from "./download";

export function safeTarget(root: string, name: string): string {
  const normalized = name.replaceAll("\\", "/");
  if (isAbsolute(normalized) || normalized.split("/").includes("..")) throw new AppError("archive_path_unsafe", `压缩包路径不安全：${name}`);
  const target = resolve(root, normalized), child = relative(resolve(root), target);
  if (child.startsWith("..") || isAbsolute(child)) throw new AppError("archive_path_unsafe", `压缩包路径不安全：${name}`);
  return target;
}

export function extract(archives: string[], staging: string): void {
  mkdirSync(staging, { recursive: true });
  for (const archive of archives) {
    const listed = spawnSync("/usr/bin/unzip", ["-Z1", archive], { encoding: "utf8" });
    if (listed.status !== 0) throw new AppError("archive_unsupported", `${archive} 不是受支持的 ZIP 包`);
    for (const name of listed.stdout.split("\n").filter(Boolean)) safeTarget(staging, name);
    const result = spawnSync("/usr/bin/unzip", ["-qq", "-o", archive, "-d", staging], { encoding: "utf8" });
    if (result.status !== 0) throw new AppError("archive_extract_failed", `压缩包解压失败：${result.stderr}`);
  }
}

export function verify(staging: string): void {
  const path = resolve(staging, "mhg-manifest.json"); if (!existsSync(path)) return;
  const manifest = JSON.parse(readFileSync(path, "utf8")) as { files?: Record<string, string> };
  for (const [name, expected] of Object.entries(manifest.files ?? {})) {
    const target = safeTarget(staging, name);
    if (!existsSync(target) || hash(target, "sha256") !== expected) throw new AppError("installed_file_invalid", `${name} 安装校验失败`);
  }
}

export function activate(staging: string, destination: string): void {
  const backup = `${destination}.backup`; rmSync(backup, { recursive: true, force: true });
  if (existsSync(destination)) renameSync(destination, backup);
  try { renameSync(staging, destination); }
  catch (error) { if (existsSync(backup) && !existsSync(destination)) renameSync(backup, destination); throw error; }
  rmSync(backup, { recursive: true, force: true });
}

export function stageExisting(source: string, staging: string): void {
  rmSync(staging, { recursive: true, force: true }); if (existsSync(source)) cpSync(source, staging, { recursive: true }); else mkdirSync(staging, { recursive: true });
}

export function ensureParent(path: string): void { mkdirSync(dirname(path), { recursive: true }); }
