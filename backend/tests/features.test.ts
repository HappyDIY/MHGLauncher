import { beforeEach, expect, test } from "vitest";
import { fixture, request } from "./helpers";

async function login(): Promise<string> {
  const session = await (await request("POST", "/v1/auth/qr-sessions", {})).json();
  await request("GET", `/v1/auth/qr-sessions/${session.id}`);
  const value = await (await request("GET", `/v1/auth/qr-sessions/${session.id}`)).json();
  await request("POST", "/v1/auth/complete", { identity: value.identity, credential_ref: "keychain:test" });
  return value.identity.credential as string;
}

beforeEach(() => fixture());

test("任务式祈愿同步、去重、统计和导出", async () => {
  const credential = await login(), task = await (await request("POST", "/v1/wishes/tasks/sync", { credential })).json();
  await new Promise((resolve) => setTimeout(resolve, 10));
  const completed = await (await request("GET", `/v1/wishes/tasks/${task.id}`)).json();
  expect(completed.status).toBe("completed"); expect(completed.result.inserted).toBe(2);
  const records = await (await request("GET", "/v1/wishes?uid=100000001")).json();
  expect(records).toHaveLength(2); expect(records[0].icon_url).toMatch(/^\/v1\/images\//);
  expect((await (await request("GET", "/v1/wishes/statistics?uid=100000001")).json())[0].five_star_count).toBe(1);
  const exported = await (await request("GET", "/v1/wishes/export?uid=100000001")).json();
  expect(exported.info.version).toBe("v4.2"); expect(exported.info.uigf_version).toBeUndefined();
});

test("UIGF 任务导入与清空", async () => {
  const payload = { info: { export_timestamp: 0, export_app: "test", export_app_version: "1", version: "v4.2" }, hk4e: [{ uid: "100000001", timezone: 8, list: [{ id: "1", uigf_gacha_type: "301", gacha_type: "301", item_id: "", time: "2026-01-01 00:00:00", name: "测试", item_type: "角色", rank_type: "5" }] }] };
  const task = await (await request("POST", "/v1/wishes/tasks/import", payload)).json(); await new Promise((resolve) => setTimeout(resolve, 10));
  expect((await (await request("GET", `/v1/wishes/tasks/${task.id}`)).json()).result.imported).toBe(1);
  expect(await (await request("DELETE", "/v1/wishes")).json()).toEqual({ deleted: 1 });
});

test("实时便笺刷新与缓存", async () => {
  const credential = await login();
  const note = await (await request("POST", "/v1/notes/refresh", { credential })).json(); expect(note.current_resin).toBe(120);
  expect((await (await request("GET", "/v1/notes?uid=100000001")).json()).finished_tasks).toBe(3);
});

test("我的角色刷新、缓存与详情", async () => {
  const credential = await login();
  const refreshed = await (await request("POST", "/v1/characters/refresh", { credential })).json();
  expect(refreshed[0].name).toBe("芙宁娜");
  expect(await (await request("GET", "/v1/characters?uid=100000001")).json()).toHaveLength(2);
  const detail = await (await request("POST", `/v1/characters/${refreshed[0].avatar_id}/refresh`, { credential })).json();
  expect(detail.payload.weapon.name).toBe("静水流涌之辉");
});

test("没有角色时返回领域错误", async () => {
  const response = await request("POST", "/v1/notes/refresh", { credential: "x" });
  expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ code: "role_missing" });
});
