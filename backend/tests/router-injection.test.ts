import { describe, expect, test } from "vitest";
import type { Container } from "../src/core/container";
import { AppError, errorResponse } from "../src/core/errors";
import { createDispatch } from "../src/api/router";

function dispatcher(token = "test-token") {
  const app = {
    settings: { apiToken: token },
    accounts: { select: () => undefined, roles: () => [] },
  } as unknown as Container;
  return createDispatch(app);
}

describe("注入式 Router 边界", () => {
  test("显式 Container 可处理鉴权健康检查", async () => {
    const response = await dispatcher()(new Request("http://local/health", {
      headers: { Authorization: "Bearer test-token" },
    }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok", version: "1.0.0" });
  });

  test("错误令牌被拒绝", async () => {
    const response = await dispatcher()(new Request("http://local/health", {
      headers: { Authorization: "Bearer wrong" },
    }));
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "unauthorized" });
  });

  test("Zod 参数错误统一返回 422", async () => {
    const response = await dispatcher()(new Request("http://local/v1/account/select", {
      method: "POST",
      headers: {
        Authorization: "Bearer test-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ aid: "" }),
    }));
    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({ code: "validation_error" });
  });

  test("AppError、序列化错误和未知错误不会互相伪装", async () => {
    const direct = errorResponse(new AppError("conflict", "冲突", 409, { retry: false }));
    expect(direct.status).toBe(409);
    expect(await direct.json()).toEqual({
      code: "conflict", message: "冲突", details: { retry: false },
    });

    const serialized = Object.assign(new Error("上游失败"), {
      code: "upstream_failed", status: 502, details: { provider: "fixture" },
    });
    expect((await errorResponse(serialized).json())).toMatchObject({ code: "upstream_failed" });
    expect((await errorResponse(new Error("secret")).json())).toEqual({
      code: "internal_error", message: "本地服务发生异常，请稍后重试", details: {},
    });
  });
});
