import { z } from "zod";
import type { Container } from "../core/container";
import { AppError } from "../core/errors";
import { exportUIGF } from "../services/uigf";

const credential = z.object({ credential: z.string().min(1).max(16_384) }).strict();
const gachaUrl = z.object({ gacha_url: z.string().url().max(16_384), token: z.string().max(1024).optional().default("") }).strict();
const cloudUid = z.object({ uid: z.string().regex(/^\d{9,10}$/), token: z.string().min(1).max(1024) }).strict();
const achievementSave = z.object({
  archive_id: z.string().min(1), expected_revision: z.number().int().min(0),
  items: z.array(z.object({ achievement_id: z.number().int(), current: z.number().int(), status: z.number().int(), timestamp: z.number().int() }).strict()).max(200_000),
}).strict();
const settings = z.object({
  daily_commission_enabled: z.boolean().optional(), daily_commission_time: z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/).optional(),
  resin_full_enabled: z.boolean().optional(),
  gacha_refresh_enabled: z.boolean().optional(), version_update_enabled: z.boolean().optional(),
}).strict();
const characterId = z.string().regex(/^(?:0|[1-9]\d{0,15})$/).refine((value) => Number(value) <= Number.MAX_SAFE_INTEGER);

export async function valueRoute(app: Container, method: string, path: string, query: URLSearchParams, body: unknown): Promise<Response | null> {
  const role = () => { const value = app.accounts.selectedRole(); if (!value) throw new AppError("role_missing", "尚未选择原神角色", 409); return value; };
  if (method === "GET" && path === "/characters") return json(app.characters.list(required(query, "uid")));
  if (method === "POST" && path === "/characters/cache-assets") return json(await app.characters.cache(role().uid));
  if (method === "POST" && path === "/characters/refresh") return json(await app.characters.refresh(credential.parse(body).credential, role()));
  const character = match(path, /^\/characters\/([^/]+)\/refresh$/);
  if (method === "POST" && character) return json(await app.characters.refreshDetail(credential.parse(body).credential, role(), characterId.parse(character)));
  if (method === "GET" && path === "/gacha-events") return json(app.gachaEvents.list());
  if (method === "GET" && path === "/gacha-resources/status") return json(app.gachaResources.status());
  if (method === "POST" && path === "/gacha-resources/install") return json(await app.gachaResources.install());
  const achievementIcon = match(path, /^\/achievements\/resources\/icons\/([A-Za-z0-9_]{1,128})\.png$/);
  if (method === "GET" && achievementIcon) return new Response(Uint8Array.from(await app.achievementResources.icon(achievementIcon)), {
    headers: { "Content-Type": "image/png", "Cache-Control": "private, max-age=31536000, immutable" },
  });
  if (method === "GET" && path === "/achievements/archive") return json(app.achievements.archiveForUid(required(query, "uid")));
  if (method === "GET" && path === "/achievements/goals") return json(await app.achievements.goals());
  if (method === "GET" && path === "/achievements/view") return json(await app.achievements.view(required(query, "archive_id")));
  if (method === "GET" && path === "/achievements/snapshot") return json(await app.achievements.snapshot(required(query, "archive_id")));
  if (method === "GET" && path === "/achievements") return json(app.achievements.list(required(query, "archive_id")));
  if (method === "POST" && path === "/achievements") { const value = achievementSave.parse(body); return json(await app.achievements.saveSnapshot(value.archive_id, value.expected_revision, value.items)); }
  if (method === "POST" && path === "/achievements/import") return json(await app.achievements.importUIAF(
    required(query, "archive_id"), revision(query), body as never,
  ));
  if (method === "GET" && path === "/achievements/export") return json(app.achievements.exportUIAF(required(query, "archive_id")));
  if (method === "POST" && path === "/cloud/login") return json(await app.cloud.login(gachaUrl.parse(body).gacha_url));
  if (method === "POST" && path === "/cloud/login/account") return json(await app.cloud.loginWithCredential(credential.parse(body).credential, role()));
  if (method === "POST" && path === "/cloud/reverify") { const value = gachaUrl.parse(body); return json(await app.cloud.reverify(value.gacha_url, value.token)); }
  if (method === "GET" && path === "/cloud/session") return json(app.cloud.session(required(query, "uid")));
  if (method === "POST" && path === "/cloud/wishes/upload") { const value = cloudUid.parse(body); return json(await app.cloud.uploadWishes(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/wishes/retrieve") { const value = cloudUid.parse(body); return json(await app.cloud.retrieveWishes(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/achievements/upload") { const value = cloudUid.parse(body); return json(await app.cloud.uploadAchievements(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/achievements/retrieve") { const value = cloudUid.parse(body); return json(await app.cloud.retrieveAchievements(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/wishes/delete") { const value = cloudUid.parse(body); return json(await app.cloud.deleteWishes(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/revoke") { const value = cloudUid.parse(body); await app.cloud.revokeSession(value.uid, value.token); return new Response(null, { status: 204 }); }
  if (method === "GET" && path === "/notifications/settings") return json(app.notifications.get());
  if (method === "PUT" && path === "/notifications/settings") return json(app.notifications.update(settings.parse(body)));
  if (method === "POST" && path === "/notifications/evaluate") {
    const uid = query.get("uid") ?? app.accounts.selectedRole()?.uid ?? "";
    return json(app.notifications.evaluate(uid ? app.notes.get(uid) : null, await app.games.state()));
  }
  if (method === "GET" && path === "/wishes/export-uigf") return json(exportUIGF(required(query, "uid"), app.wishes.list(required(query, "uid"))));
  return null;
}

function json(value: unknown, status = 200): Response { return Response.json(value, { status }); }
function match(path: string, expression: RegExp): string | null { return expression.exec(path)?.[1] ? decodeURIComponent(expression.exec(path)?.[1] ?? "") : null; }
function required(query: URLSearchParams, name: string): string { const value = query.get(name); if (!value) throw new AppError("validation_error", `${name} 不能为空`, 422); return value; }
function revision(query: URLSearchParams): number {
  const value = required(query, "expected_revision");
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new AppError("validation_error", "expected_revision 无效", 422);
  }
  return Number(value);
}
