import type { GameBuild } from "./provider";
import { diffGameBuild } from "./build-diff";

type BuildLoader = () => Promise<GameBuild>;

export async function selectPatchOrRemote(
  remote: GameBuild, patch?: BuildLoader,
): Promise<GameBuild> {
  if (!patch) return remote;
  try {
    const selected = await patch();
    return selected.version === remote.version ? { ...selected, repair_assets: remote.assets } : remote;
  } catch { return remote; }
}

export async function selectUpdateBuild(
  remote: GameBuild, local: BuildLoader, patch?: BuildLoader,
): Promise<GameBuild> {
  const selected = await selectPatchOrRemote(remote, patch);
  if (selected !== remote) return selected;
  try { return diffGameBuild(await local(), remote, "version_diff_chunks"); }
  catch { return remote; }
}

export function hasCompletePatchStats(manifests: Array<{ stats?: unknown }>, version: string): boolean {
  return manifests.every(({ stats }) => Boolean(stats) && typeof stats === "object"
    && Object.hasOwn(stats as object, version));
}
