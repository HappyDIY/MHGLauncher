import type { GameJob } from "../core/models";

export interface ProgressCallbacks {
  progress: (bytes: number) => void;
  chunk: (name: string, done: number, total: number) => void;
  flush: () => void;
}

export function makeProgress(
  job: GameJob,
  notify: () => void = () => undefined,
  now: () => number = Date.now,
): ProgressCallbacks {
  let speedBytes = 0, speedStarted = now(), lastPublished = 0;
  const active = new Map<string, { name: string; bytes_done: number; total: number }>();
  const completedChunks = new Set<string>();
  const publish = (force = false): void => {
    const timestamp = now();
    if (!force && timestamp - lastPublished < 500) return;
    job.last_update = new Date(timestamp).toISOString();
    job.active_chunks = [...active.values()].slice(-4);
    lastPublished = timestamp; notify();
  };
  const progress = (bytes: number): void => {
    job.completed_bytes = Math.min(job.total_bytes, Math.max(0, job.completed_bytes + bytes)); speedBytes += Math.max(0, bytes);
    const timestamp = now(), elapsed = timestamp - speedStarted;
    if (elapsed >= 500) { job.download_speed = Math.round(speedBytes * 1_000 / elapsed); speedBytes = 0; speedStarted = timestamp; }
    publish(elapsed >= 500);
  };
  const chunk = (name: string, done: number, total: number): void => {
    const boundedTotal = Math.max(0, total), boundedDone = Math.min(boundedTotal, Math.max(0, done));
    active.delete(name); active.set(name, { name, bytes_done: boundedDone, total: boundedTotal });
    if (boundedDone === boundedTotal) completedChunks.add(name);
    job.chunks_completed = Math.min(job.chunks_total, completedChunks.size);
    publish();
  };
  return { progress, chunk, flush: () => publish(true) };
}
