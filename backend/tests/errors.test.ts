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
});
