import { expect, test } from "vitest";
import type { GameJob } from "../src/core/models";
import { makeProgress } from "../src/services/job-progress";

test("分块密集完成时限制进度快照频率", () => {
  const job = fixtureJob();
  const clock = { now: 1_000 };
  let notifications = 0;
  const progress = makeProgress(job, () => { notifications += 1; }, () => clock.now);

  progress.chunk("first", 10, 10);
  clock.now += 1;
  progress.chunk("second", 10, 10);

  expect(notifications).toBe(1);
  expect(job.chunks_completed).toBe(2);

  clock.now = 1_500;
  progress.chunk("third", 0, 10);
  expect(notifications).toBe(2);
  expect(job.active_chunks.map(({ name }) => name)).toEqual(["first", "second", "third"]);
});

test("显式刷新立即发布节流期间的最新状态", () => {
  const job = fixtureJob();
  const clock = { now: 1_000 };
  let notifications = 0;
  const progress = makeProgress(job, () => { notifications += 1; }, () => clock.now);

  progress.chunk("first", 10, 10);
  clock.now += 1;
  progress.chunk("second", 10, 10);
  progress.flush();

  expect(notifications).toBe(2);
  expect(job.active_chunks.map(({ name }) => name)).toEqual(["first", "second"]);
});

function fixtureJob(): GameJob {
  return {
    id: "job", kind: "install", status: "running", completed_bytes: 0, total_bytes: 100,
    message: "", download_speed: 0, chunks_completed: 0, chunks_total: 10,
    active_chunks: [], last_update: "", revision: 0,
  };
}
