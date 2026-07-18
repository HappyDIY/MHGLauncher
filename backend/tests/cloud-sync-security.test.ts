import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { fixture } from "./helpers";

afterEach(() => { vi.restoreAllMocks(); });

test("未配置云地址时拒绝伪造同步结果", async () => {
  const app = fixture();
  const fetch = vi.spyOn(globalThis, "fetch");
  await expect(app.cloud.uploadWishes("100000001", "token")).rejects.toMatchObject({ code: "cloud_not_configured" });
  await expect(app.cloud.retrieveWishes("100000001", "token")).rejects.toMatchObject({ code: "cloud_not_configured" });
  expect(fetch).not.toHaveBeenCalled();
});

test("云服务网络失败时返回明确错误", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("connection refused"));
  await expect(app.cloud.uploadWishes("100000001", "token")).rejects.toMatchObject({ code: "cloud_error", status: 503 });
});

test("云端鉴权错误保留可行动原因", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json(
    { code: "gacha_url_expired", message: "抽卡 URL 已过期" }, { status: 422 },
  ));
  await expect(app.cloud.login("https://example.com/gacha")).rejects.toMatchObject({
    code: "gacha_url_expired", message: "抽卡 URL 已过期", status: 422,
  });
	  expect(JSON.parse(readFileSync(join(app.settings.dataDir, "cloud-sync-diagnostic.json"), "utf8"))).toMatchObject({
	    path: "/api/v1/auth/gacha-url", status: 422, code: "gacha_url_expired", upstream_code: "gacha_url_expired",
	  });
});

test("本地代理先绑定云端会话 UID", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  const fetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ uid: "100000002" }));
  await expect(app.cloud.uploadWishes("100000001", "token")).rejects.toMatchObject({ code: "cloud_identity_mismatch" });
  expect(fetch).toHaveBeenCalledTimes(1);
});

test("云端数据请求不再发送客户端 UID", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  const fetch = vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(Response.json({ uid: "100000001" }))
    .mockResolvedValueOnce(Response.json({ uploaded: 0 }));
  await app.cloud.uploadWishes("100000001", "token");
  const [url, init] = fetch.mock.calls[1] ?? [];
  expect(url).toBe("https://cloud.example/api/v1/gacha/upload");
  expect(JSON.parse(String(init?.body))).toEqual({ items: [] });
});

test("取回兼容官方接口的空物品 ID", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(Response.json({ uid: "100000001" }))
    .mockResolvedValueOnce(Response.json({ items: [{
      id: "1", uid: "100000001", gacha_type: "301", uigf_gacha_type: "301", item_id: "",
      name: "角色", item_type: "角色", rank: 5, time: "2026-01-01T00:00:00Z",
    }] }));
  await expect(app.cloud.retrieveWishes("100000001", "token")).resolves.toEqual({ imported: 1 });
  expect(app.wishes.list("100000001")[0]?.item_id).toBe("");
});

test("成就云同步按 UID 上传并以版本快照取回", async () => {
  const app = fixture(); app.settings.cloudBaseUrl = "https://cloud.example";
  const archive = app.achievements.archiveForUid("100000001");
  app.achievements.saveSnapshot(archive.id, 0, [
    { achievement_id: 84501, current: 1, status: 3, timestamp: 1_756_000_000 },
  ]);
  const fetch = vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(Response.json({ uid: "100000001" }))
    .mockResolvedValueOnce(Response.json({ uploaded: 1 }))
    .mockResolvedValueOnce(Response.json({ uid: "100000001" }))
    .mockResolvedValueOnce(Response.json({ items: [
      { achievement_id: 84502, current: 1, status: 3, timestamp: 1_756_000_001 },
    ] }));

  await expect(app.cloud.uploadAchievements("100000001", "token")).resolves.toEqual({ uploaded: 1 });
  expect(JSON.parse(String(fetch.mock.calls[1]?.[1]?.body))).toEqual({ items: [
    { achievement_id: 84501, current: 1, status: 3, timestamp: 1_756_000_000 },
  ] });
  await expect(app.cloud.retrieveAchievements("100000001", "token")).resolves.toEqual({ imported: 1 });
  expect(app.achievements.list(archive.id).map(({ achievement_id }) => achievement_id)).toEqual([84501, 84502]);
});
