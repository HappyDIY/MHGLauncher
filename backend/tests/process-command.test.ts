import { expect, test } from "vitest";
import { runCommand } from "../src/services/process-command";

test("子进程停滞会被期限终止且不阻塞事件循环", async () => {
  let timerRan = false; setTimeout(() => { timerRan = true; }, 5);
  const started = Date.now(), result = await runCommand("/bin/sh", ["-c", "exec sleep 5"], { timeout: 50 });
  expect(result.error?.message).toBe("command timeout"); expect(Date.now() - started).toBeLessThan(1_000); expect(timerRan).toBe(true);
});
