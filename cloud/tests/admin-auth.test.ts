import { afterEach, describe, expect, test } from "vitest";
import { requireAdmin } from "../src/admin-auth";

describe("管理服务认证", () => {
  afterEach(() => { delete process.env.MHG_ADMIN_SERVICE_TOKEN; });

  test("拒绝缺失或错误的服务令牌", () => {
    process.env.MHG_ADMIN_SERVICE_TOKEN = "expected";
    expect(() => requireAdmin(new Request("http://cloud"))).toThrow();
    expect(() => requireAdmin(request("wrong", "request_123"))).toThrow();
  });

  test("返回经过约束的站长上下文", () => {
    process.env.MHG_ADMIN_SERVICE_TOKEN = "expected";
    expect(requireAdmin(request("expected", "request_123"))).toEqual({ actor: "owner@example.com", requestId: "request_123" });
    expect(() => requireAdmin(request("expected", "bad"))).toThrow();
  });
});

function request(token: string, requestId: string): Request {
  return new Request("http://cloud", { headers: { Authorization: `Bearer ${token}`, "X-MHG-Admin-Actor": "owner@example.com", "X-Request-ID": requestId } });
}
