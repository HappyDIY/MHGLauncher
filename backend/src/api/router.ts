import { randomUUID, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { container } from "../core/container";
import { AppError, errorResponse } from "../core/errors";
import type { JobKind } from "../core/models";
import { exportUIGF } from "../services/uigf";
import { launchAccount } from "../services/game-account-registry";
import { longPollOptions } from "../services/revision-notifier";
import { valueRoute } from "./value-routes";
import { readJsonBody } from "../core/request-body";

const credential = z.object({ credential: z.string().min(1).max(16_384) }).strict();
const roleSync = z.object({ aid: z.string().min(1).max(32), credential: z.string().min(1).max(16_384) }).strict();
const selectAccount = z.object({ aid: z.string().min(1).max(32) }).strict();
const selectRole = z.object({ uid: z.string().regex(/^\d{9,10}$/) }).strict();
const mobile = z.object({ mobile: z.string().regex(/^1\d{10}$/) }).strict();
const mobileLogin = z.object({ mobile: z.string().regex(/^1\d{10}$/), captcha: z.string().min(4).max(16), action_type: z.string().min(1).max(128), aigis: z.string().max(16_384).optional().nullable() }).strict();
const mobileVerification = z.object({ mobile: z.string().regex(/^1\d{10}$/), session_id: z.string().min(1).max(256), challenge: z.string().min(1).max(4096), validate: z.string().min(1).max(4096) }).strict();
const cookieLogin = z.object({ credential: z.string().min(1).max(16_384) }).strict();
const loginTransaction = z.object({ transaction_id: z.string().uuid() }).strict();
const refresh = z.object({ credential: z.string().max(16_384), xrpc_challenge: z.string().max(4096).default(""), xrpc_challenge_path: z.string().max(2048).default("") }).strict();
const verification = z.object({ credential: z.string().max(16_384), challenge: z.string().max(4096), validate: z.string().max(4096), xrpc_challenge_path: z.string().max(2048).default("") }).strict();
const startJob = z.object({ kind: z.enum(["install", "update", "verify", "predownload"]), install_path: z.string().min(1).max(4096) }).strict();
const controlJob = z.object({ action: z.enum(["pause", "resume", "cancel"]) }).strict();
const speedLimit = z.object({ speed_limit_kb: z.number().int().min(0).max(10_000_000) }).strict();
const startLaunch = z.object({
  install_path: z.string().min(1), performance_profile: z.enum(["optimized", "compatibility", "baseline"]).default("optimized"),
  metal_hud: z.boolean().default(false), network_debug: z.boolean().default(false),
  wine_log: z.boolean().default(false),
  frame_pacing: z.number().int().min(0).max(240).default(0), credential: z.string().min(1).max(16_384).optional(),
}).strict();
const characterId = z.string().regex(/^(?:0|[1-9]\d{0,15})$/).refine((value) => Number(value) <= Number.MAX_SAFE_INTEGER);

export async function dispatch(request: Request): Promise<Response> {
  try {
    authorize(request);
    const url = new URL(request.url), path = url.pathname.replace(/^\/v1/, "");
    const limit = ["/wishes/tasks/import", "/achievements/import"].includes(path) ? 64 * 1024 * 1024 : 1024 * 1024;
    const body = request.method === "POST" || request.method === "PUT" ? await readJsonBody(request, limit) : undefined;
    return await route(request.method, path, url.searchParams, body);
  } catch (error) {
    if (error instanceof z.ZodError) return Response.json({ code: "validation_error", message: "请求参数无效", details: { issues: JSON.stringify(error.issues) } }, { status: 422 });
    return errorResponse(error);
  }
}

async function route(method: string, path: string, query: URLSearchParams, body: unknown): Promise<Response> {
  const app = container();
  if (method === "GET" && path === "/accounts") return json(app.accounts.list());
  if (method === "GET" && path === "/account") return json(app.accounts.get());
  if (method === "DELETE" && path === "/account") { app.accounts.logout(); return new Response(null, { status: 204 }); }
  if (method === "POST" && path === "/account/select") return json({ account: app.accounts.select(selectAccount.parse(body).aid), roles: app.accounts.roles() });
  if (method === "GET" && path === "/roles") return json(app.accounts.roles());
  if (method === "POST" && path === "/roles/select") return json(app.accounts.selectRole(selectRole.parse(body).uid));
  if (method === "POST" && path === "/roles/sync") { const value = roleSync.parse(body); return json(await app.accounts.syncRoles(value.aid, value.credential)); }
  if (method === "POST" && path === "/auth/qr-sessions") {
    const session = await app.provider.createQRSession(); app.preparedLogins.begin(`qr:${session.id}`); return json(session);
  }
  const qr = match(path, /^\/auth\/qr-sessions\/([^/]+)$/);
  if (method === "GET" && qr) {
    const [session, identity] = await app.provider.queryQRSession(qr);
    const prepared = identity ? app.preparedLogins.prepare(`qr:${qr}`, identity, await app.accounts.prepareRoles(identity)) : null;
    return json({ session, prepared_login: prepared });
  }
  if (method === "POST" && path === "/auth/mobile-captcha") {
    const value = mobile.parse(body).mobile, session = await app.provider.createMobileCaptcha(value);
    app.preparedLogins.begin(`mobile:${value}`); return json(session);
  }
  if (method === "POST" && path === "/auth/mobile-captcha/verification") {
    const value = mobileVerification.parse(body);
    return json(await app.provider.verifyMobileCaptcha(value.mobile, value.session_id, value.challenge, value.validate));
  }
  if (method === "POST" && path === "/auth/mobile-login") {
    const value = mobileLogin.parse(body), identity = await app.provider.loginByMobileCaptcha(value.mobile, value.captcha, value.action_type, value.aigis);
    return json(app.preparedLogins.prepare(`mobile:${value.mobile}`, identity, await app.accounts.prepareRoles(identity)));
  }
  if (method === "POST" && path === "/auth/cookie-login") {
    const source = `cookie:${randomUUID()}`; app.preparedLogins.begin(source);
    const identity = await app.provider.identifyCredential(cookieLogin.parse(body).credential);
    return json(app.preparedLogins.prepare(source, identity, await app.accounts.prepareRoles(identity)));
  }
  if (method === "POST" && path === "/auth/commit") {
    const prepared = app.preparedLogins.consume(loginTransaction.parse(body).transaction_id);
    return json(app.accounts.commit(prepared.identity, prepared.roles));
  }
  if (method === "POST" && path === "/auth/abort") { app.preparedLogins.abort(loginTransaction.parse(body).transaction_id); return new Response(null, { status: 204 }); }
  if (method === "GET" && path === "/game/status") return json(await app.games.state());
  if (method === "GET" && path === "/game/status/path") return json(await app.games.state(required(query, "install_path")));
  if (method === "GET" && path === "/game/space-check") { const installPath = required(query, "install_path"); const state = await app.games.state(installPath); return json(await app.games.spaceCheck(installPath, state.download_bytes, (query.get("kind") ?? "update") as JobKind)); }
  if (method === "POST" && path === "/game/jobs") { const value = startJob.parse(body); return json(await app.games.start(value.kind as JobKind, value.install_path), 202); }
  if (method === "GET" && path === "/settings/speed-limit") return json({ speed_limit_kb: app.games.getSpeedLimit() });
  if (method === "POST" && path === "/settings/speed-limit") { const value = speedLimit.parse(body); app.games.setSpeedLimit(value.speed_limit_kb); return json({ speed_limit_kb: value.speed_limit_kb }); }
  const gameJob = match(path, /^\/game\/jobs\/([^/]+)$/);
  if (method === "GET" && gameJob) { const wait = longPollOptions(query); return json(await app.games.wait(gameJob, wait.after, wait.waitMs)); }
  const gameControl = match(path, /^\/game\/jobs\/([^/]+)\/control$/);
  if (method === "POST" && gameControl) return json(app.games.control(gameControl, controlJob.parse(body).action));
  if (method === "POST" && path === "/game/launch") {
    const value = startLaunch.parse(body), account = app.accounts.get();
    let registryAccount;
    if (account && value.credential) {
      const identity = await app.provider.identifyCredential(value.credential);
      if (identity.aid !== account.aid || identity.mid !== account.mid) throw new AppError("credential_identity_mismatch", "凭据与当前账号不匹配", 403);
      registryAccount = launchAccount(account, value.credential);
    }
    const { credential: ignored, ...launch } = value; void ignored;
    return json(app.launches.start({ ...launch, account: registryAccount }), 202);
  }
  const launchStop = match(path, /^\/game\/launches\/([^/]+)\/stop$/);
  if (method === "POST" && launchStop) return json(app.launches.stop(launchStop), 202);
  if (method === "GET" && path === "/game/launches/recovery") return json(app.launches.recovery());
  const launch = match(path, /^\/game\/launches\/([^/]+)$/);
  if (method === "GET" && launch) { const wait = longPollOptions(query); return json(await app.launches.wait(launch, wait.after, wait.waitMs)); }
  if (method === "POST" && path === "/wishes/tasks/sync") return json(app.wishTasks.startSync(credential.parse(body).credential), 202);
  if (method === "POST" && path === "/wishes/tasks/import") return json(app.wishTasks.startImport(body), 202);
  const task = match(path, /^\/wishes\/tasks\/([^/]+)$/);
  if (method === "GET" && task) { const wait = longPollOptions(query); return json(await app.wishTasks.wait(task, wait.after, wait.waitMs)); }
  if (method === "GET" && path === "/companion/snapshot") {
    const uid = required(query, "uid"); return json(app.wishes.snapshot(uid, app.notes.get(uid)));
  }
  if (method === "GET" && path === "/wishes") return json(app.wishes.list(required(query, "uid"), query.get("gacha_type") ?? undefined));
  if (method === "GET" && path === "/wishes/statistics") return json(app.wishes.statistics(required(query, "uid")));
  if (method === "GET" && path === "/wishes/banner-statistics") return json(app.wishes.bannerStatistics(required(query, "uid")));
  if (method === "DELETE" && path === "/wishes") return json({ deleted: app.wishes.clear() });
  if (method === "GET" && path === "/wishes/export") { const uid = required(query, "uid"); return json(exportUIGF(uid, app.wishes.list(uid))); }
  if (method === "GET" && path === "/notes") return json(app.notes.get(required(query, "uid")));
  if (method === "GET" && path === "/characters") return json(app.characters.list(required(query, "uid")));
  if (method === "POST" && path === "/characters/refresh") {
    const value = credential.parse(body), role = app.accounts.selectedRole();
    if (!role) throw new AppError("role_missing", "尚未选择原神角色", 409);
    return json(await app.characters.refresh(value.credential, role));
  }
  const character = match(path, /^\/characters\/([^/]+)\/refresh$/);
  if (method === "POST" && character) {
    const value = credential.parse(body), role = app.accounts.selectedRole();
    if (!role) throw new AppError("role_missing", "尚未选择原神角色", 409);
    return json(await app.characters.refreshDetail(value.credential, role, characterId.parse(character)));
  }
  if (method === "POST" && path === "/notes/refresh") {
    const value = refresh.parse(body), role = app.accounts.selectedRole();
    if (!role) throw new AppError("role_missing", "尚未选择原神角色", 409);
    return json(await app.notes.refresh(value.credential, role, value.xrpc_challenge, value.xrpc_challenge_path));
  }
  if (method === "POST" && path === "/notes/verification") { const value = verification.parse(body); return json({ xrpc_challenge: await app.notes.verify(value.credential, value.challenge, value.validate, value.xrpc_challenge_path) }); }
	  const image = match(path, /^\/images\/gacha\/([^/]+)$/);
	  if (method === "GET" && image) { const data = await app.images.get(image); if (!data) throw new AppError("image_missing", "图片未缓存", 404); return new Response(new Uint8Array(data), { headers: { "Content-Type": "image/png" } }); }
	  const value = await valueRoute(app, method, path, query, body);
	  if (value) return value;
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
function match(path: string, expression: RegExp): string | null { const value = expression.exec(path)?.[1]; return value ? decodeURIComponent(value) : null; }
function required(query: URLSearchParams, name: string): string { const value = query.get(name); if (!value) throw new AppError("validation_error", `${name} 不能为空`, 422); return value; }
