import { describe, expect, test, vi } from "vitest";
import type { GameRole } from "../src/core/models";
import type { AccountService } from "../src/services/accounts";
import type { WishService } from "../src/services/wishes";
import { WishTasks } from "../src/services/wish-tasks";

const role: GameRole = {
  uid: "100000001", nickname: "旅行者", region: "cn_gf01", level: 60, selected: true,
};

function tasks(wishes: Partial<WishService>, selected: GameRole | null = role): WishTasks {
  return new WishTasks(
    { selectedRole: () => selected } as AccountService,
    wishes as WishService,
  );
}

describe("祈愿任务变异边界", () => {
  test("同步成功、失败和缺少角色都进入明确终态", async () => {
    const success = tasks({ sync: vi.fn(async () => 2) });
    const completed = success.startSync("credential");
    await terminal(success, completed.id);
    expect(success.get(completed.id)).toMatchObject({
      status: "completed", result: { inserted: 2 }, progress: 1,
    });

    const failure = tasks({ sync: vi.fn(async () => { throw new Error("secret"); }) });
    const failed = failure.startSync("credential");
    await terminal(failure, failed.id);
    expect(failure.get(failed.id)).toMatchObject({
      status: "failed", error_code: "unknown_error",
    });

    const missing = tasks({ sync: vi.fn(async () => 0) }, null);
    const missingJob = missing.startSync("credential");
    await terminal(missing, missingJob.id);
    expect(missing.get(missingJob.id)).toMatchObject({
      status: "failed", error_code: "role_missing",
    });
  });

  test("运行中的任务拒绝重复创建并支持长轮询", async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const service = tasks({ sync: vi.fn(async () => { await gate; return 1; }) });
    const job = service.startSync("credential");
    expect(() => service.startSync("second")).toThrowError(
      expect.objectContaining({ code: "wish_task_busy" }),
    );
    const waiting = service.wait(job.id, job.revision ?? 0, 1_000);
    release();
    expect((await waiting).status).toBe("completed");
  });

  test("未知任务被拒绝", () => {
    expect(() => tasks({}).get("missing")).toThrowError(
      expect.objectContaining({ code: "wish_task_missing" }),
    );
  });
});

async function terminal(service: WishTasks, id: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (["completed", "failed"].includes(service.get(id).status)) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("等待任务终态超时");
}
