import { expect, test } from "vitest";
import { RevisionNotifier } from "../src/services/revision-notifier";

test("客户端断开会释放长轮询等待者", async () => {
  const notifier = new RevisionNotifier<{ revision?: number }>();
  const controller = new AbortController();
  const value = { revision: 1 };
  const waiting = notifier.wait("job", 1, 2_000, () => value, controller.signal);

  controller.abort();

  await expect(waiting).resolves.toBe(value);
});
