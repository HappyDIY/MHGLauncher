import { createHash, timingSafeEqual } from "node:crypto";
import { HttpError } from "./http";

export type AdminContext = { actor: string; requestId: string };

export function requireAdmin(request: Request): AdminContext {
  const expected = process.env.MHG_ADMIN_SERVICE_TOKEN ?? "";
  const supplied = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  if (!expected || !safeEqual(expected, supplied)) throw new HttpError(401, "admin_unauthorized", "管理服务认证失败");
  const actor = request.headers.get("x-mhg-admin-actor")?.trim() ?? "";
  const requestId = request.headers.get("x-request-id")?.trim() ?? "";
  if (!/^[^\r\n]{1,128}$/.test(actor) || !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
    throw new HttpError(400, "admin_headers_invalid", "管理请求标识无效");
  }
  return { actor, requestId };
}

function safeEqual(left: string, right: string): boolean {
  const a = createHash("sha256").update(left).digest();
  const b = createHash("sha256").update(right).digest();
  return timingSafeEqual(a, b);
}
