import type { GameBuild, SophonChunk } from "../providers/provider";
import type { JobKind } from "../core/models";
import { AppError } from "../core/errors";
import type { DownloadControl } from "./download";
import { download } from "./download";
import { extract, safeTarget, verify } from "./installer";
import { installPatches } from "./patch-install";
import { installSophon } from "./sophon-install";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import {
  canonicalAssets, canonicalBuild, removeRetired, removeSafe,
} from "./game-build";
import { selectInvalidAssetsStrict } from "./game-integrity";

interface InstallOptions {
  build: GameBuild; kind: JobKind; staging: string; cache: string; control: DownloadControl;
  progress: (bytes: number) => void; chunk: (name: string, done: number, total: number) => void;
  workers: number; limiter: TokenBucketRateLimiter | null; reserve: (chunks: SophonChunk[]) => void;
}

export async function installGameResources(options: InstallOptions): Promise<GameBuild> {
  const { build, kind, staging, cache, control, progress, chunk, workers, limiter } = options;
  let patchFailure: unknown, performed = false;
  if (build.patch_assets.length || build.deprecated_files.length) {
    performed = true;
    try {
      if (build.patch_assets.length) await installPatches(
        build.patch_assets, staging, cache, control, progress, chunk, limiter,
      );
    } catch (error) {
      if (!build.repair_assets.length || fatal(error)) throw error;
      patchFailure = error;
    }
    for (const name of build.deprecated_files) removeSafe(staging, name);
  }
  if (build.assets.length) {
    performed = true;
    await installSophon(build.assets, staging, cache, control, progress, chunk, workers, limiter, build.base_assets, options.reserve);
  } else if (build.segments.length) {
    performed = true;
    const archives: string[] = [];
    for (const segment of build.segments) archives.push(await download(
      segment, safeTarget(cache, segment.filename), control, progress,
    ));
    extract(archives, staging); verify(staging);
  } else if (!performed && kind !== "verify") {
    throw new AppError("game_build_empty", "下载服务返回了不完整的空构建", 502);
  }
  if (kind === "update" && build.kind !== "package_repair" && build.kind !== "version_diff" && build.assets.length) {
    removeRetired(staging, canonicalBuild(build));
  }
  const canonical = canonicalAssets(build);
  if (canonical.length) {
    const invalid = await selectInvalidAssetsStrict(staging, canonical, control.signal);
    if (invalid.length) {
      options.reserve(invalid.flatMap(({ chunks }) => chunks));
      await installSophon(invalid, staging, cache, control, progress, chunk, workers, limiter);
    }
    if ((await selectInvalidAssetsStrict(staging, canonical, control.signal)).length) {
      throw new AppError("game_integrity_failed", "游戏资源修复后仍未通过完整性校验");
    }
  } else if (patchFailure) {
    throw patchFailure;
  }
  return canonicalBuild(build);
}

function fatal(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError"
    || error instanceof AppError && error.code === "storage_write_failed";
}
