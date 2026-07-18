import { describe, expect, test } from "vitest";
import { latestUpdate } from "../src/app-update";
import { dispatch } from "../src/router";

const env: NodeJS.ProcessEnv = {
  NODE_ENV: "test",
  MHG_UPDATE_VERSION: "0.2.0",
  MHG_UPDATE_DOWNLOAD_URL: "https://download.example/MHGLauncher-0.2.0.dmg",
  MHG_UPDATE_SHA256: "A".repeat(64),
  MHG_UPDATE_SIZE: "1024",
  MHG_UPDATE_CHANGELOG: "新增自动更新检测",
};

describe("应用更新接口", () => {
  test("返回经过规范化的发布信息", () => {
    expect(latestUpdate(env)).toEqual({
      version: "0.2.0",
      download_url: env.MHG_UPDATE_DOWNLOAD_URL,
      sha256: "a".repeat(64),
      size: 1024,
      changelog: env.MHG_UPDATE_CHANGELOG,
    });
  });

  test("拒绝非 HTTPS、错误哈希和未知包格式", () => {
    expect(() => latestUpdate({ ...env, MHG_UPDATE_DOWNLOAD_URL: "http://download.example/update.dmg" })).toThrow();
    expect(() => latestUpdate({ ...env, MHG_UPDATE_DOWNLOAD_URL: "https://download.example/update.exe" })).toThrow();
    expect(() => latestUpdate({ ...env, MHG_UPDATE_SHA256: "bad" })).toThrow();
  });

  test("未配置时返回稳定错误且不访问数据库", async () => {
    const keys = Object.keys(env);
    const previous = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
    for (const key of keys) delete process.env[key];
    try {
      const response = await dispatch(new Request("http://cloud/api/v1/updates/latest"));
      expect(response.status).toBe(503);
      expect(await response.json()).toEqual({ code: "update_not_configured", message: "应用更新信息尚未配置" });
    } finally {
      for (const key of keys) {
        const value = previous[key];
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
    }
  });

  test("Compose 空字符串配置仍返回稳定错误", async () => {
    let error: unknown;
    try { latestUpdate({ NODE_ENV: "test", MHG_UPDATE_VERSION: "", MHG_UPDATE_DOWNLOAD_URL: "", MHG_UPDATE_SHA256: "",
      MHG_UPDATE_SIZE: "", MHG_UPDATE_CHANGELOG: "" }); } catch (caught) { error = caught; }
    expect(error).toMatchObject({ code: "update_not_configured" });
  });
});
