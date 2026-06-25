import type { GameJob } from "../core/models";

export interface ProgressCallbacks {
  progress: (bytes: number) => void;
  chunk: (name: string, done: number, total: number) => void;
}

export function makeProgress(job: GameJob): ProgressCallbacks {
  let speedBytes = 0, speedStarted = Date.now();
  const progress = (bytes: number): void => {
    job.completed_bytes = Math.max(0, job.completed_bytes + bytes); speedBytes += Math.max(0, bytes);
    const now = Date.now(), elapsed = now - speedStarted;
    if (elapsed >= 500) { job.download_speed = Math.round(speedBytes * 1_000 / elapsed); speedBytes = 0; speedStarted = now; }
    job.last_update = new Date(now).toISOString();
  };
  const completedChunks = new Set<string>();
  const chunk = (name: string, done: number, total: number): void => {
    const value = { name, bytes_done: done, total }; job.active_chunks = [...job.active_chunks.filter((item) => item.name !== name), value].slice(-4);
    if (done === total) completedChunks.add(name);
    job.chunks_completed = completedChunks.size;
  };
  return { progress, chunk };
}