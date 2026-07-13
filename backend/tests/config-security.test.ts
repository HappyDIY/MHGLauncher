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
});
