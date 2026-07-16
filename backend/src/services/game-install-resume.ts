import { existsSync, lstatSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import type { JobKind } from "../core/models";
import { safeIdentifier } from "../core/safe-path";
import { detectGame } from "./game-detection";
import { managedPath } from "./managed-file";

const OFFICIAL_DIRECTORY = "Genshin Impact Game";
const STAGING_TOKEN = ".mhg-staging-";

export interface InstallResume { destination: string; source: string; version: string }
export interface GameOperationPaths {
  detected: ReturnType<typeof detectGame>; resume: InstallResume | null;
  root: string; source: string; version: string;
}

export function gameOperationPaths(kind: JobKind, input: string): GameOperationPaths {
  const detected = detectGame(input);
  const resume = kind === "install" && !detected ? findInstallResume(input) : null;
  return {
    detected, resume, root: detected?.path ?? resume?.destination ?? resolve(input),
    source: detected?.path ?? resume?.source ?? "", version: detected?.version ?? resume?.version ?? "",
  };
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
    if (!existsSync(source)) return null;
    const directory = lstatSync(source); if (!directory.isDirectory() || directory.isSymbolicLink()) return null;
    const marker = managedPath(source, ".mhg-staging-version");
    if (!existsSync(marker) || !lstatSync(marker).isFile()) return null;
    const version = safeIdentifier(readFileSync(marker, "utf8").trim(), "暂存版本");
    return { destination, source, version };
  } catch { return null; }
}

function stagingDestination(path: string): string | null {
  const name = basename(path), index = name.indexOf(STAGING_TOKEN);
  return index > 0 ? join(dirname(path), name.slice(0, index)) : null;
}
