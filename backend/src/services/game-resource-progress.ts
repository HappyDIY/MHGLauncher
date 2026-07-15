import type { GameJob } from "../core/models";
import type { GameAsset, GameBuild, SophonChunk } from "../providers/provider";
import { operationChunks } from "./game-build";
import { makeProgress, type ProgressCallbacks } from "./job-progress";

export type GameResourcePhase = "verify" | "repair";

export interface GameResourceProgress extends ProgressCallbacks {
  phase: (phase: GameResourcePhase, assets: GameAsset[]) => void;
  reserve: (chunks: SophonChunk[]) => void;
}

export function makeGameResourceProgress(
  job: GameJob, build: GameBuild, notify: () => void,
): GameResourceProgress {
  let callbacks = makeProgress(job, notify);
  let reserved = new Map(uniqueChunks(build.assets.flatMap(operationChunks)).map((chunk) => [chunk.name, chunk]));
  const phase = (value: GameResourcePhase, assets: GameAsset[]): void => {
    const chunks = value === "repair" ? uniqueChunks(assets.flatMap(({ chunks }) => chunks)) : [];
    reserved = new Map(chunks.map((chunk) => [chunk.name, chunk]));
    job.message = value === "verify" ? "正在校验游戏资源完整性" : "正在修复游戏资源";
    job.completed_bytes = 0;
    job.total_bytes = value === "verify"
      ? assets.reduce((total, asset) => total + asset.size, 0)
      : chunks.reduce((total, chunk) => total + chunk.size, 0);
    job.download_speed = 0; job.chunks_completed = 0;
    job.chunks_total = value === "verify" ? assets.length : chunks.length;
    job.active_chunks = []; callbacks = makeProgress(job, notify); notify();
  };
  const reserve = (chunks: SophonChunk[]): void => {
    for (const chunk of uniqueChunks(chunks)) if (!reserved.has(chunk.name)) {
      reserved.set(chunk.name, chunk); job.total_bytes += chunk.size; job.chunks_total += 1;
    }
    notify();
  };
  return {
    progress: (bytes) => callbacks.progress(bytes),
    chunk: (name, done, total) => callbacks.chunk(name, done, total),
    flush: () => callbacks.flush(), phase, reserve,
  };
}

function uniqueChunks(chunks: SophonChunk[]): SophonChunk[] {
  return [...new Map(chunks.map((chunk) => [chunk.name, chunk])).values()];
}
