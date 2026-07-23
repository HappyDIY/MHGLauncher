import { describe, expect, test, vi } from "vitest";
import { acquirePrivateUmask } from "../src/core/private-umask";

describe("私有 umask", () => {
  test("操作结束后恢复原值", () => {
    const setter = vi.fn(() => 0o022);
    const restore = acquirePrivateUmask(0o077, setter, "production");
    restore();
    expect(setter.mock.calls).toEqual([[0o077], [0o022]]);
  });

  test("测试 Worker 不支持 umask 时允许继续", () => {
    const failure = Object.assign(new Error("unsupported"), {
      code: "ERR_WORKER_UNSUPPORTED_OPERATION",
    });
    const restore = acquirePrivateUmask(0o077, () => { throw failure; }, "test");
    expect(restore()).toBeUndefined();
  });

  test("生产环境不会吞掉 umask 错误", () => {
    const failure = new Error("failed");
    expect(() => acquirePrivateUmask(0o077, () => { throw failure; }, "production"))
      .toThrow(failure);
  });
});
