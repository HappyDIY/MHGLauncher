import { expect, test } from "vitest";
import { concurrentMap } from "../src/services/concurrent-map";
import { DownloadControl } from "../src/services/download";

test("首个 worker 失败后等待其他 worker 停止再返回", async () => {
  const control = new DownloadControl(); let siblingStopped = false;
  const pending = concurrentMap([1, 2], 2, control, async (item) => {
    if (item === 1) throw new Error("first failure");
    await new Promise<void>((resolve) => control.signal.addEventListener("abort", () => setTimeout(resolve, 20), { once: true }));
    siblingStopped = true; return item;
  });
  await expect(pending).rejects.toThrow("first failure"); expect(siblingStopped).toBe(true);
});
