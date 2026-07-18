import { z } from "zod";
import { requireAdmin } from "./admin-auth";
import { readJsonBody } from "./body";
import { ready } from "./db";
import { fail, HttpError, json } from "./http";
import { createRelease, listReleases, publishRelease } from "./admin-releases";
import { listAudit, overview } from "./admin-overview";
import { deleteUser, listUsers, revokeUserSessions } from "./admin-users";
import type { AdminContext } from "./admin-auth";
import { auditFailure } from "./admin-audit";

const uidSchema = z.string().regex(/^\d{9,10}$/);

export async function dispatchAdmin(request: Request): Promise<Response> {
  let context: AdminContext | undefined;
  try {
    context = requireAdmin(request);
    await ready();
    const url = new URL(request.url), path = url.pathname.replace(/^\/api\/admin\/v1/, "");
    if (request.method === "GET" && path === "/overview") return json(await overview());
    if (request.method === "GET" && path === "/users") {
      const query = z.string().regex(/^\d{0,10}$/).parse(url.searchParams.get("query") ?? "");
      const cursor = z.string().regex(/^\d{9,10}$/).optional().parse(url.searchParams.get("cursor") ?? undefined);
      const limit = z.coerce.number().int().min(1).max(100).default(25).parse(url.searchParams.get("limit") ?? 25);
      return json(await listUsers(query, cursor, limit));
    }
    if (request.method === "GET" && path === "/releases") return json(await listReleases());
    if (request.method === "POST" && path === "/releases") return json(await createRelease(await readJsonBody(request, 1024 * 1024), context), 201);
    if (request.method === "GET" && path === "/audit") {
      const cursor = z.coerce.number().int().positive().optional().parse(url.searchParams.get("cursor") ?? undefined);
      const limit = z.coerce.number().int().min(1).max(100).default(50).parse(url.searchParams.get("limit") ?? 50);
      return json(await listAudit(cursor, limit));
    }
    const userMatch = path.match(/^\/users\/(\d{9,10})\/(revoke-sessions)$/);
    if (request.method === "POST" && userMatch) return json(await revokeUserSessions(uidSchema.parse(userMatch[1]), context));
    const deleteMatch = path.match(/^\/users\/(\d{9,10})$/);
    if (request.method === "DELETE" && deleteMatch) return json(await deleteUser(uidSchema.parse(deleteMatch[1]), context));
    const releaseMatch = path.match(/^\/releases\/(\d+)\/(publish|rollback)$/);
    if (request.method === "POST" && releaseMatch) {
      const id = z.coerce.number().int().positive().parse(releaseMatch[1]);
      return json(await publishRelease(id, context, releaseMatch[2] === "rollback" ? "release.rollback" : "release.publish"));
    }
    throw new HttpError(404, "not_found", "管理接口不存在");
  } catch (error) {
    if (context && request.method !== "GET") await auditFailure(context, request, error).catch(() => undefined);
    if (error instanceof z.ZodError) return json({ code: "validation_error", message: "请求参数无效", detail: error.issues }, 422);
    return fail(error);
  }
}
