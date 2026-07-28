import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, expect, test, vi } from "vitest";
import { closeContainer, Container } from "../src/core/container";
import { fixture, request } from "./helpers";

beforeEach(() => fixture());

test("历史素材路由识别受支持的图片格式", async () => {
  const app = globalThis.mhgContainer!;
  const root = join(app.settings.dataDir, "resources", "gacha-history", "images");
  mkdirSync(root, { recursive: true });
  const values = [
    ["a", Buffer.from("89504e470d0a1a0a", "hex"), "image/png"],
    ["b", Buffer.from("ffd8ff", "hex"), "image/jpeg"],
    ["c", Buffer.from("524946460000000057454250", "hex"), "image/webp"],
    ["d", Buffer.from("unknown"), "application/octet-stream"],
  ] as const;
  for (const [prefix, data, contentType] of values) {
    const name = `${prefix.repeat(64)}.img`; writeFileSync(join(root, name), data);
    const response = await request("GET", `/v1/gacha-resources/files/images/${name}`);
    expect(response.headers.get("content-type")).toBe(contentType);
  }
});

test("容器把安装完成事件转发给完整资料同步并可统一关闭", () => {
  const app = globalThis.mhgContainer!;
  const sync = vi.spyOn(app, "syncMetadata").mockResolvedValue(app.metadataRepository.status());
  const games = app.games as unknown as { onInstalled?: (version: string) => void };
  games.onInstalled?.("6.0.0");
  expect(sync).toHaveBeenCalledWith(false, "6.0.0");
  closeContainer();
  expect(globalThis.mhgContainer).toBeUndefined();
});

test("正式环境容器启用在线资料与提供方", async () => {
  const fixtureApp = globalThis.mhgContainer!;
  vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("offline"));
  const dataDir = join(fixtureApp.settings.dataDir, "live");
  const live = new Container({
    ...fixtureApp.settings, providerMode: "live", dataDir,
    databasePath: join(dataDir, "live.db"), hutaoApiBaseUrl: "https://api.example",
  });
  expect(live.provider.constructor.name).toBe("LiveProvider");
  live.metadataRepository.trigger();
  expect(live.metadataRepository.status().state).toBe("syncing");
  await new Promise((resolve) => setImmediate(resolve));
  live.close();
});
