import { expect, test } from "vitest";
import { runCommand } from "../src/services/process-command";

test("子进程停滞会被期限终止且不阻塞事件循环", async () => {
  let timerRan = false; setTimeout(() => { timerRan = true; }, 5);
  const started = Date.now(), result = await runCommand("/bin/sh", ["-c", "exec sleep 5"], { timeout: 50 });
  expect(result.error?.message).toBe("command timeout"); expect(Date.now() - started).toBeLessThan(1_000); expect(timerRan).toBe(true);
});

test("命令使用默认选项并收集标准输出", async () => {
  const result = await runCommand("/bin/echo", ["MHGLauncher"]);
  expect(result).toMatchObject({ status: 0, stdout: "MHGLauncher\n", stderr: "" });
});

test("命令可接收标准输入", async () => {
  const result = await runCommand("/bin/cat", [], { input: "测试输入" });
  expect(result).toMatchObject({ status: 0, stdout: "测试输入", stderr: "" });
});
