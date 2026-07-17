import { beforeEach, expect, test } from "vitest";
import { fixture, request } from "./helpers";

beforeEach(() => fixture());

test("未登录时可通过抽卡 URL 导入祈愿记录", async () => {
  const url = "https://webstatic.mihoyo.com/hk4e/event/e20190909gacha-v3/index.html?auth_appid=webview_gacha&authkey=fixture&uid=100000001";
  const task = await (await request("POST", "/v1/wishes/tasks/import-url", { gacha_url: url })).json();
  const completed = await waitForTask(task.id);
  expect(completed.target_uids).toEqual(["100000001"]);
  const snapshot = await (await request("GET", "/v1/companion/snapshot?uid=100000001")).json();
  expect(snapshot.wishes.length).toBeGreaterThan(0);
});

async function waitForTask(id: string): Promise<{ status: string; target_uids?: string[] }> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const task = await (await request("GET", `/v1/wishes/tasks/${id}`)).json();
    if (task.status === "completed") return task;
    if (task.status === "failed") throw new Error(`祈愿任务失败：${task.error_code} ${task.error}`);
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("等待祈愿任务完成超时");
}
