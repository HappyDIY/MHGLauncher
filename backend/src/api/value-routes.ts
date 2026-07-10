import { z } from "zod";
import type { Container } from "../core/container";
import { AppError } from "../core/errors";
import { exportUIGF } from "../services/uigf";

const credential = z.object({ credential: z.string().min(1) });
const gachaUrl = z.object({ gacha_url: z.string().url(), token: z.string().optional().default("") });
const cloudUid = z.object({ uid: z.string().min(1), token: z.string().min(1) });
const archive = z.object({ name: z.string().min(1) });
const achievementSave = z.object({
  archive_id: z.string().min(1),
  items: z.array(z.object({ achievement_id: z.number().int(), current: z.number().int(), status: z.number().int(), timestamp: z.number().int() })),
});
const settings = z.object({
  daily_commission_enabled: z.boolean().optional(), daily_commission_time: z.string().optional(),
  resin_full_enabled: z.boolean().optional(),
  gacha_refresh_enabled: z.boolean().optional(), version_update_enabled: z.boolean().optional(),
});

export async function valueRoute(app: Container, method: string, path: string, query: URLSearchParams, body: unknown): Promise<Response | null> {
  const role = () => { const value = app.accounts.selectedRole(); if (!value) throw new AppError("role_missing", "尚未选择原神角色", 409); return value; };
  if (method === "GET" && path === "/characters") return json(app.characters.list(required(query, "uid")));
  if (method === "POST" && path === "/characters/refresh") return json(await app.characters.refresh(credential.parse(body).credential, role()));
  const character = match(path, /^\/characters\/([^/]+)\/refresh$/);
  if (method === "POST" && character) return json(await app.characters.refreshDetail(credential.parse(body).credential, role(), character));
  if (method === "GET" && path === "/gacha-events") return json(app.gachaEvents.list());
  if (method === "POST" && path === "/gacha-events/refresh") return json(await app.gachaEvents.refresh(credential.parse(body).credential, role()));
  if (method === "GET" && path === "/achievements/archives") return json(app.achievements.archives());
  if (method === "POST" && path === "/achievements/archives") return json(app.achievements.createArchive(archive.parse(body).name), 201);
  const archiveSelect = match(path, /^\/achievements\/archives\/([^/]+)\/select$/);
  if (method === "POST" && archiveSelect) return json(app.achievements.selectArchive(archiveSelect));
  const archiveDelete = match(path, /^\/achievements\/archives\/([^/]+)$/);
  if (method === "DELETE" && archiveDelete) return json({ deleted: app.achievements.removeArchive(archiveDelete) });
  if (method === "GET" && path === "/achievements/goals") return json(app.achievements.goals());
  if (method === "GET" && path === "/achievements/view") return json(app.achievements.view(query.get("archive_id") ?? undefined));
  if (method === "GET" && path === "/achievements") return json(app.achievements.list(query.get("archive_id") ?? undefined));
  if (method === "POST" && path === "/achievements") { const value = achievementSave.parse(body); return json(app.achievements.save(value.archive_id, value.items)); }
  if (method === "POST" && path === "/achievements/import") return json(app.achievements.importUIAF(required(query, "archive_id"), body as never));
  if (method === "GET" && path === "/achievements/export") return json(app.achievements.exportUIAF(query.get("archive_id") ?? undefined));
  if (method === "POST" && path === "/cloud/login") return json(await app.cloud.login(gachaUrl.parse(body).gacha_url));
  if (method === "POST" && path === "/cloud/reverify") { const value = gachaUrl.parse(body); return json(await app.cloud.reverify(value.gacha_url, value.token)); }
  if (method === "GET" && path === "/cloud/session") return json(app.cloud.session(required(query, "uid")));
  if (method === "POST" && path === "/cloud/wishes/upload") { const value = cloudUid.parse(body); return json(await app.cloud.uploadWishes(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/wishes/retrieve") { const value = cloudUid.parse(body); return json(await app.cloud.retrieveWishes(value.uid, value.token)); }
  if (method === "POST" && path === "/cloud/wishes/delete") { const value = cloudUid.parse(body); return json(await app.cloud.deleteWishes(value.uid, value.token)); }
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
