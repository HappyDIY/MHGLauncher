import type { GameAsset, GameBuild, SophonChunk } from "./provider";
import { normalizeBuild } from "./provider";

export function diffGameBuild(local: GameBuild, remote: GameBuild, kind: string): GameBuild {
  if (!remote.assets.length) return remote;
  const localAssets = new Map(local.assets.map((asset) => [asset.name.toLowerCase(), asset]));
  const remoteNames = new Set(remote.assets.map((asset) => asset.name.toLowerCase()));
  const assets = remote.assets.flatMap((remoteAsset) => {
    const localAsset = localAssets.get(remoteAsset.name.toLowerCase());
    if (!localAsset) return [remoteAsset];
    if (localAsset.md5.toLowerCase() === remoteAsset.md5.toLowerCase()) return [];
    return [{ ...remoteAsset, required_chunks: diffChunks(localAsset, remoteAsset) }];
  });
  return normalizeBuild({
    ...remote, kind, assets, segments: [], base_assets: local.assets, repair_assets: remote.assets,
    deprecated_files: local.assets.filter((asset) => !remoteNames.has(asset.name.toLowerCase())).map(({ name }) => name),
  });
}

function diffChunks(local: GameAsset, remote: GameAsset): SophonChunk[] {
  const known = new Set(local.chunks.map((chunk) => chunk.decompressed_md5.toLowerCase()));
  return remote.chunks.filter((chunk) => !known.has(chunk.decompressed_md5.toLowerCase()));
}
