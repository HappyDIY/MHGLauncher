import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { container } from "../core/container";
import { AppError, errorResponse } from "../core/errors";
import type { JobKind } from "../core/models";
import { exportUIGF } from "../services/uigf";

const credential = z.object({ credential: z.string().min(1) });
const complete = z.object({ identity: z.object({ aid: z.string(), mid: z.string(), nickname: z.string(), credential: z.string() }), credential_ref: z.string() });
const refresh = z.object({ credential: z.string(), xrpc_challenge: z.string().default("") });
const verification = z.object({ credential: z.string(), challenge: z.string(), validate: z.string() });
const startJob = z.object({ kind: z.enum(["install", "update", "verify"]), install_path: z.string().min(1) });
const controlJob = z.object({ action: z.enum(["pause", "resume", "cancel"]) });

export async function dispatch(request: Request): Promise<Response> {
  try {
    authorize(request);
    const url = new URL(request.url), path = url.pathname.replace(/^\/v1/, "");
    const body = request.method === "POST" ? await request.json() : undefined;
    return await route(request.method, path, url.searchParams, body);
  } catch (error) {
    if (error instanceof z.ZodError) return Response.json({ detail: error.issues }, { status: 422 });
    return errorResponse(error);
  }
}

async function route(method: string, path: string, query: URLSearchParams, body: unknown): Promise<Response> {
  const app = container();
  if (method === "GET" && path === "/account") return json(app.accounts.get());
  if (method === "DELETE" && path === "/account") { app.accounts.logout(); return new Response(null, { status: 204 }); }
  if (method === "GET" && path === "/roles") return json(app.accounts.roles());
  if (method === "POST" && path === "/roles/sync") return json(await app.accounts.syncRoles(credential.parse(body).credential));
  if (method === "POST" && path === "/auth/qr-sessions") return json(await app.provider.createQRSession());
  const qr = match(path, /^\/auth\/qr-sessions\/([^/]+)$/);
  if (method === "GET" && qr) { const [session, identity] = await app.provider.queryQRSession(qr); return json({ session, identity }); }
  if (method === "POST" && path === "/auth/complete") {
    const value = complete.parse(body), account = app.accounts.save(value.identity, value.credential_ref);
    return json({ account, roles: await app.accounts.syncRoles(value.identity.credential) });
  }
  if (method === "GET" && path === "/game/status") return json(await app.games.state());
  if (method === "GET" && path === "/game/status/path") return json(await app.games.state(required(query, "install_path")));
  if (method === "POST" && path === "/game/jobs") { const value = startJob.parse(body); return json(await app.games.start(value.kind as JobKind, value.install_path), 202); }
  const gameJob = match(path, /^\/game\/jobs\/([^/]+)$/);
  if (method === "GET" && gameJob) return json(app.games.get(gameJob));
  const gameControl = match(path, /^\/game\/jobs\/([^/]+)\/control$/);
  if (method === "POST" && gameControl) return json(app.games.control(gameControl, controlJob.parse(body).action));
  if (method === "POST" && path === "/game/launch") throw new AppError("launch_not_implemented", "游戏启动功能尚未实现", 501);
  if (method === "POST" && path === "/wishes/tasks/sync") return json(app.wishTasks.startSync(credential.parse(body).credential), 202);
  if (method === "POST" && path === "/wishes/tasks/import") return json(app.wishTasks.startImport(body), 202);
  const task = match(path, /^\/wishes\/tasks\/([^/]+)$/);
  if (method === "GET" && task) return json(app.wishTasks.get(task));
  if (method === "GET" && path === "/wishes") return json(app.wishes.list(required(query, "uid"), query.get("gacha_type") ?? undefined));
  if (method === "GET" && path === "/wishes/statistics") return json(app.wishes.statistics(required(query, "uid")));
  if (method === "GET" && path === "/wishes/banner-statistics") return json(app.wishes.bannerStatistics(required(query, "uid")));
  if (method === "DELETE" && path === "/wishes") return json({ deleted: app.wishes.clear() });
  if (method === "GET" && path === "/wishes/export") { const uid = required(query, "uid"); return json(exportUIGF(uid, app.wishes.list(uid))); }
  if (method === "GET" && path === "/notes") return json(app.notes.get(required(query, "uid")));
  if (method === "POST" && path === "/notes/refresh") {
    const value = refresh.parse(body), role = app.accounts.selectedRole();
    if (!role) throw new AppError("role_missing", "尚未选择原神角色", 409);
    return json(await app.notes.refresh(value.credential, role, value.xrpc_challenge));
  }
  if (method === "POST" && path === "/notes/verification") { const value = verification.parse(body); return json({ xrpc_challenge: await app.notes.verify(value.credential, value.challenge, value.validate) }); }
  const image = match(path, /^\/images\/gacha\/([^/]+)$/);
  if (method === "GET" && image) { const data = await app.images.get(image); if (!data) throw new AppError("image_missing", "图片未缓存", 404); return new Response(new Uint8Array(data), { headers: { "Content-Type": "image/png" } }); }
  throw new AppError("not_found", "接口不存在", 404);
}

function authorize(request: Request): void {
  const expected = container().settings.apiToken;
  if (!expected) return;
  const actual = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  const left = Buffer.from(actual), right = Buffer.from(expected);
  if (left.length !== right.length || !timingSafeEqual(left, right)) throw new AppError("unauthorized", "本地服务鉴权失败", 401);
}
function json(value: unknown, status = 200): Response { return Response.json(value, { status }); }
function match(path: string, expression: RegExp): string | null { return expression.exec(path)?.[1] ? decodeURIComponent(expression.exec(path)?.[1] ?? "") : null; }
function required(query: URLSearchParams, name: string): string { const value = query.get(name); if (!value) throw new AppError("validation_error", `${name} 不能为空`, 422); return value; }
