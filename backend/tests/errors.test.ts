import { describe, expect, test } from "vitest";
import { errorResponse } from "../src/core/errors";

describe("业务错误序列化", () => {
  test("跨打包模块仍保留状态码", async () => {
    const error = Object.assign(new Error("目录无效"), {
      code: "game_not_installed", status: 409, details: {},
    });
    const response = errorResponse(error);
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ code: "game_not_installed" });
  });

  test("未知异常不暴露原始错误", async () => {
    const response = errorResponse(new Error("SQLITE_ERROR: /private/data.db"));
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ code: "internal_error", message: "本地服务发生异常，请稍后重试", details: {} });
  });
});
