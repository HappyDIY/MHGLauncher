import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { container } from "../core/container";
import { AppError, errorResponse } from "../core/errors";
import type { JobKind } from "../core/models";
import { exportUIGF } from "../services/uigf";
import { launchAccount } from "../services/game-account-registry";
import { longPollOptions } from "../services/revision-notifier";
import { valueRoute } from "./value-routes";

const credential = z.object({ credential: z.string().min(1) });
const selectAccount = z.object({ aid: z.string().min(1) });
const selectRole = z.object({ uid: z.string().min(1) });
const mobile = z.object({ mobile: z.string().regex(/^1\d{10}$/) });
const mobileLogin = z.object({ mobile: z.string().regex(/^1\d{10}$/), captcha: z.string().min(4), action_type: z.string().min(1), aigis: z.string().optional().nullable() });
const mobileVerification = z.object({ mobile: z.string().regex(/^1\d{10}$/), session_id: z.string().min(1), challenge: z.string().min(1), validate: z.string().min(1) });
const cookieLogin = z.object({ credential: z.string().min(1) });
const complete = z.object({ identity: z.object({ aid: z.string(), mid: z.string(), nickname: z.string(), credential: z.string() }), credential_ref: z.string() });
const refresh = z.object({ credential: z.string(), xrpc_challenge: z.string().default(""), xrpc_challenge_path: z.string().default("") });
const verification = z.object({ credential: z.string(), challenge: z.string(), validate: z.string(), xrpc_challenge_path: z.string().default("") });
const startJob = z.object({ kind: z.enum(["install", "update", "verify", "predownload"]), install_path: z.string().min(1) });
const controlJob = z.object({ action: z.enum(["pause", "resume", "cancel"]) });
const speedLimit = z.object({ speed_limit_kb: z.number().int().min(0) });
const startLaunch = z.object({
  install_path: z.string().min(1), performance_profile: z.enum(["optimized", "compatibility", "baseline"]).default("optimized"),
  metal_hud: z.boolean().default(false), network_debug: z.boolean().default(false),
  wine_log: z.boolean().default(false),
  frame_pacing: z.number().int().min(0).max(240).default(0), credential: z.string().min(1).optional(),
});

export async function dispatch(request: Request): Promise<Response> {
  try {
    authorize(request);
    const url = new URL(request.url), path = url.pathname.replace(/^\/v1/, "");
    const body = request.method === "POST" || request.method === "PUT" ? await request.json() : undefined;
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
  if (method === "POST" && path === "/roles/sync") return json(await app.accounts.syncRoles(credential.parse(body).credential));
  if (method === "POST" && path === "/auth/qr-sessions") return json(await app.provider.createQRSession());
  const qr = match(path, /^\/auth\/qr-sessions\/([^/]+)$/);
  if (method === "GET" && qr) { const [session, identity] = await app.provider.queryQRSession(qr); return json({ session, identity }); }
  if (method === "POST" && path === "/auth/mobile-captcha") return json(await app.provider.createMobileCaptcha(mobile.parse(body).mobile));
  if (method === "POST" && path === "/auth/mobile-captcha/verification") {
    const value = mobileVerification.parse(body);
    return json(await app.provider.verifyMobileCaptcha(value.mobile, value.session_id, value.challenge, value.validate));
  }
  if (method === "POST" && path === "/auth/mobile-login") {
    const value = mobileLogin.parse(body), identity = await app.provider.loginByMobileCaptcha(value.mobile, value.captcha, value.action_type, value.aigis);
    const account = app.accounts.save(identity, `keychain:account:${identity.aid}`);
    return json({ account, identity, roles: await app.accounts.syncRoles(identity.credential, account.aid) });
  }
  if (method === "POST" && path === "/auth/cookie-login") {
    const value = cookieLogin.parse(body), identity = await app.provider.identifyCredential(value.credential);
    const account = app.accounts.save(identity, `keychain:account:${identity.aid}`);
    return json({ account, identity, roles: await app.accounts.syncRoles(identity.credential, account.aid) });
  }
  if (method === "POST" && path === "/auth/complete") {
    const value = complete.parse(body), account = app.accounts.save(value.identity, value.credential_ref);
    return json({ account, roles: await app.accounts.syncRoles(value.identity.credential, account.aid) });
  }
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
    const authTicket = account && value.credential ? await app.provider.createAuthTicket(value.credential) : undefined;
    return json(app.launches.start({ ...value, account: account && value.credential ? launchAccount(account, value.credential) : undefined, auth_ticket: authTicket }), 202);
  }
  const launchStop = match(path, /^\/game\/launches\/([^/]+)\/stop$/);
  if (method === "POST" && launchStop) return json(app.launches.stop(launchStop), 202);
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
    return json(await app.characters.refreshDetail(value.credential, role, character));
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
