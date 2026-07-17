import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { LiveGameRecordSource } from "../src/providers/live-game-record";

const roots: string[] = [];

function source(): LiveGameRecordSource {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-record-test-")); roots.push(dataDir);
  return new LiveGameRecordSource({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "", providerMode: "live",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, downloadSpeedLimitKB: 0, socketPath: join(dataDir, "test.sock") });
}

afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("抽卡 URL 拒绝非官方域名", async () => {
  const fetch = vi.spyOn(globalThis, "fetch");
  await expect(source().verifyGachaUrl("https://notmihoyo.com/gacha?authkey=x")).rejects.toMatchObject({ code: "gacha_url_invalid" });
  expect(fetch).not.toHaveBeenCalled();
});

test("活动页 URL 规范化为官方祈愿接口", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = new URL(String(input));
    expect(url.origin + url.pathname).toBe("https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog");
    expect(url.searchParams.get("gacha_type")).toBe("301");
    return Response.json({ retcode: 0, data: { list: [{
      id: "1", uid: "100000001", gacha_type: "301", item_id: "1001",
      name: "测试角色", item_type: "角色", rank_type: "5", time: "2026-01-01 00:00:00",
    }] } });
  });
  const proof = await source().verifyGachaUrl(
    "https://webstatic.mihoyo.com/hk4e/event/e20190909gacha-v3/index.html?auth_appid=webview_gacha&authkey=fixture",
  );
  expect(proof.uid).toBe("100000001");
  expect(fetch).toHaveBeenCalledTimes(1);
});

test("卡池日历使用 POST 与角色参数", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual({ role_id: "10001", server: "cn_gf01" });
    return Response.json({ retcode: 0, data: { card_pool_list: [] } });
  });
  await expect(source().gachaEvents("stoken=test", { uid: "10001", nickname: "旅行者", region: "cn_gf01", level: 1, selected: true })).resolves.toEqual([]);
});

test("上游非 JSON 错误保持领域错误", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("Method Not Allowed", { status: 405 }));
  await expect(source().gachaEvents("stoken=test", { uid: "10001", nickname: "旅行者", region: "cn_gf01", level: 1, selected: true }))
    .rejects.toMatchObject({ code: "mihoyo_response_invalid", details: { http_status: "405" } });
});
