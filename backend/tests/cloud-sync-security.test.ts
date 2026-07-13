import { afterEach, expect, test, vi } from "vitest";
import { fixture } from "./helpers";

afterEach(() => { vi.restoreAllMocks(); });

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
