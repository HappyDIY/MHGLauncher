import type { GameBuild } from "../providers/provider";
import { diffGameBuild } from "../providers/build-diff";
import { AppError } from "../core/errors";

export function checkedPredownloadBuild(installedVersion: string, local: GameBuild, remote: GameBuild): GameBuild {
  if (local.version !== installedVersion) throw new AppError("predownload_base_mismatch", `当前游戏版本 ${installedVersion} 与官方常规通道 ${local.version} 不一致，请先完成常规更新或修复后再预下载`, 409, { installed_version: installedVersion, main_version: local.version });
  return diffPredownloadBuild(local, remote);
}

export function diffPredownloadBuild(local: GameBuild, remote: GameBuild): GameBuild {
  return diffGameBuild(local, remote, "predownload_diff");
}
