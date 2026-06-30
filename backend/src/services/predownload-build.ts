import type { GameAsset, GameBuild, SophonChunk } from "../providers/provider";
import { normalizeBuild } from "../providers/provider";
import { AppError } from "../core/errors";

export function checkedPredownloadBuild(installedVersion: string, local: GameBuild, remote: GameBuild): GameBuild {
  if (local.version !== installedVersion) throw new AppError("predownload_base_mismatch", `当前游戏版本 ${installedVersion} 与官方常规通道 ${local.version} 不一致，请先完成常规更新或修复后再预下载`, 409, { installed_version: installedVersion, main_version: local.version });
  return diffPredownloadBuild(local, remote);
}

export function diffPredownloadBuild(local: GameBuild, remote: GameBuild): GameBuild {
  if (!remote.assets.length) return remote;
  const localAssets = new Map(local.assets.map((asset) => [asset.name.toLowerCase(), asset]));
  const assets = remote.assets.flatMap((remoteAsset) => {
    const localAsset = localAssets.get(remoteAsset.name.toLowerCase());
    if (!localAsset) return [remoteAsset];
    if (localAsset.md5.toLowerCase() === remoteAsset.md5.toLowerCase()) return [];
    const chunks = diffChunks(localAsset, remoteAsset);
    return chunks.length ? [{ ...remoteAsset, chunks }] : [];
  });
  return normalizeBuild({ ...remote, kind: "predownload_diff", assets, segments: [] });
}

function diffChunks(local: GameAsset, remote: GameAsset): SophonChunk[] {
  const known = new Set(local.chunks.map((chunk) => chunk.decompressed_md5.toLowerCase()));
  return remote.chunks.filter((chunk) => !known.has(chunk.decompressed_md5.toLowerCase()));
}
