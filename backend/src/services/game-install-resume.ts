import { existsSync, lstatSync, readdirSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import type { JobKind } from "../core/models";
import { AppError } from "../core/errors";
import { detectGame } from "./game-detection";
import { managedPath } from "./managed-file";
import { readGameStaging } from "./game-staging";

const OFFICIAL_DIRECTORY = "Genshin Impact Game";
const STAGING_TOKEN = ".mhg-staging-";

export interface InstallResume { destination: string; source: string; version: string }
export interface GameOperationPaths {
  detected: ReturnType<typeof detectGame>; resume: InstallResume | null;
  root: string; source: string; version: string;
}

export function gameOperationPaths(kind: JobKind, input: string): GameOperationPaths {
  const absolute = resolve(input), requested = existsSync(absolute) ? realpathSync(absolute) : absolute;
  const detected = detectGame(requested);
  const resume = kind === "install" && !detected ? findInstallResume(requested) : null;
  const fresh = kind === "install" && !detected && !resume ? freshInstallDestination(requested) : requested;
  return {
    detected, resume, root: detected?.path ?? resume?.destination ?? fresh,
    source: detected?.path ?? resume?.source ?? "", version: detected?.version ?? resume?.version ?? "",
  };
}

export function assertFreshInstallDestination(paths: GameOperationPaths): void {
  if (paths.detected || paths.resume || !existsSync(paths.root)) return;
  const stat = lstatSync(paths.root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new AppError("install_destination_invalid", "安装位置必须是普通目录", 409);
  }
  if (readdirSync(paths.root).length > 0) {
    throw new AppError("install_destination_not_empty", "所选安装目录不为空，已拒绝覆盖其中的文件", 409);
  }
}

export function findInstallResume(input: string): InstallResume | null {
  const requested = resolve(input), inferred = stagingDestination(requested);
  if (inferred) {
    const direct = readResume(requested, inferred); if (direct) return direct;
  }
  const destinations = [...new Set([requested, join(requested, OFFICIAL_DIRECTORY)])];
  for (const destination of destinations) {
    const direct = readResume(destination, destination); if (direct) return direct;
  }
  const stale = destinations.flatMap(staleResumes).sort((left, right) => right.modified - left.modified);
  return stale[0] ?? null;
}

function staleResumes(destination: string): (InstallResume & { modified: number })[] {
  const parent = dirname(destination), prefix = `${basename(destination)}${STAGING_TOKEN}`;
  try {
    return readdirSync(parent, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && entry.name.startsWith(prefix))
      .flatMap((entry) => {
        const source = join(parent, entry.name), resume = readResume(source, destination);
        return resume ? [{ ...resume, modified: statSync(managedPath(source, ".mhg-staging-version")).mtimeMs }] : [];
      });
  } catch { return []; }
}

function readResume(source: string, destination: string): InstallResume | null {
  try {
    const record = readGameStaging(source, destination);
    if (record?.kind !== "install") return null;
    const actualSource = existsSync(record.destination) && realpathSync(source) === realpathSync(record.destination)
      ? record.destination : source;
    return { destination: record.destination, source: actualSource, version: record.version };
  } catch { return null; }
}

function stagingDestination(path: string): string | null {
  const name = basename(path), index = name.indexOf(STAGING_TOKEN);
  return index > 0 ? join(dirname(path), name.slice(0, index)) : null;
}

function freshInstallDestination(requested: string): string {
  try {
    const stat = lstatSync(requested);
    if (stat.isDirectory() && !stat.isSymbolicLink() && basename(requested) !== OFFICIAL_DIRECTORY
      && readdirSync(requested).length > 0) return join(requested, OFFICIAL_DIRECTORY);
  } catch { /* 不存在的路径按用户指定的目录创建。 */ }
  return requested;
}
