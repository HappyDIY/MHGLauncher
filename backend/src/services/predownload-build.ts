import type { GameBuild } from "../providers/provider";
import { diffGameBuild } from "../providers/build-diff";
import { AppError } from "../core/errors";

export function checkedPredownloadBuild(installedVersion: string, local: GameBuild, remote: GameBuild): GameBuild {
  if (local.version !== installedVersion) throw new AppError("predownload_base_mismatch", `当前游戏版本 ${installedVersion} 与本地资源清单 ${local.version} 不一致，无法计算预下载差分`, 409, { installed_version: installedVersion, local_version: local.version });
  if (compareGameVersions(remote.version, installedVersion) <= 0) throw new AppError("predownload_unavailable", "预下载版本不高于当前游戏版本", 409);
  return diffPredownloadBuild(local, remote);
}

export function diffPredownloadBuild(local: GameBuild, remote: GameBuild): GameBuild {
  return diffGameBuild(local, remote, "predownload_diff");
}

export function compareGameVersions(left: string, right: string): number {
  const leftParts = left.split("."), rightParts = right.split(".");
  if (![...leftParts, ...rightParts].every((value) => /^\d+$/.test(value))) return left.localeCompare(right);
  for (let index = 0; index < Math.max(leftParts.length, rightParts.length); index += 1) {
    const leftValue = BigInt(leftParts[index] ?? "0"), rightValue = BigInt(rightParts[index] ?? "0");
    if (leftValue !== rightValue) return leftValue < rightValue ? -1 : 1;
  }
  return 0;
}
