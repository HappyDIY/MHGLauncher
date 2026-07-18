import { describe, expect, test } from "vitest";
import { settings, validateServerSettings } from "../src/core/config";

describe("服务安全配置", () => {
  test("拒绝空鉴权令牌", () => {
    expect(() => validateServerSettings(settings({ NODE_ENV: "test", MHG_API_TOKEN: "" }))).toThrow("MHG_API_TOKEN");
  });

  test("拒绝无效请求超时", () => {
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test",
      MHG_API_TOKEN: "token",
      MHG_REQUEST_TIMEOUT: "999",
    }))).toThrow("MHG_REQUEST_TIMEOUT");
  });

  test("接受有效服务配置", () => {
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test",
      MHG_API_TOKEN: "token",
      MHG_REQUEST_TIMEOUT: "30000",
    }))).not.toThrow();
  });

  test("默认连接本机云服务并允许环境覆盖", () => {
    expect(settings({ NODE_ENV: "test" }).cloudBaseUrl).toBe("http://localhost:3333");
    expect(settings({ NODE_ENV: "test", MHG_CLOUD_BASE_URL: "https://cloud.example/" }).cloudBaseUrl)
      .toBe("https://cloud.example");
  });

  test("拒绝无效云服务地址", () => {
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test",
      MHG_API_TOKEN: "token",
      MHG_CLOUD_BASE_URL: "file:///tmp/cloud",
    }))).toThrow("MHG_CLOUD_BASE_URL");
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test",
      MHG_API_TOKEN: "token",
      MHG_CLOUD_BASE_URL: "http://cloud.example",
    }))).toThrow("HTTPS");
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test",
      MHG_API_TOKEN: "token",
      MHG_CLOUD_BASE_URL: "http://localhost:3333",
    }))).not.toThrow();
  });

  test("历史卡池资源仅接受 HTTPS 清单", () => {
    expect(settings({ NODE_ENV: "test" }).gachaResourceManifestUrl).toContain("github.com/HappyDIY/MHGLauncher");
    expect(() => validateServerSettings(settings({
      NODE_ENV: "test", MHG_API_TOKEN: "token",
      MHG_GACHA_RESOURCE_MANIFEST_URL: "http://resource.example/manifest.json",
    }))).toThrow("历史卡池资源");
  });
});
