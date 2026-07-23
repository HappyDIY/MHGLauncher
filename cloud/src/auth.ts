import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { PoolClient } from "pg";
import { pool, transaction } from "./db";
import { HttpError } from "./http";
import { requestGacha, type GachaRequester } from "./gacha-request";

type GachaItem = { id: string; uid: string; gacha_type: string; uigf_gacha_type: string; item_id: string; name: string; item_type: string; rank: number; time: string };
const gachaHosts = new Set(["public-operation-hk4e.mihoyo.com"]);

export async function verifyGachaUrl(raw: string, requester: GachaRequester = requestGacha): Promise<{ uid: string; items: GachaItem[] }> {
  const url = new URL(raw);
  if (url.protocol !== "https:" || url.username || url.password || url.port || !gachaHosts.has(url.hostname)
    || !url.searchParams.get("authkey")) throw new HttpError(422, "gacha_url_invalid", "抽卡 URL 无效");
	  url.searchParams.set("gacha_type", "301");
  url.searchParams.set("size", "20");
	  url.searchParams.set("end_id", "0");
  const response = await requester(url);
  let payload: { retcode?: number; message?: string; data?: { uid?: unknown; list?: Record<string, any>[] } };
  try { payload = await response.json() as typeof payload; }
  catch { throw new HttpError(502, "gacha_upstream_invalid", "抽卡服务返回了无效响应，请稍后重试"); }
  if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new HttpError(422, "gacha_url_expired", payload.message ?? "抽卡 URL 不可用");
  const responseUid = String(payload.data?.uid ?? "");
  const itemUids = new Set((payload.data?.list ?? []).map((item) => String(item.uid ?? "")).filter(Boolean));
  const provenUid = responseUid || (itemUids.size === 1 ? [...itemUids][0] ?? "" : "");
  if (!/^\d{9,10}$/.test(provenUid) || (itemUids.size && (itemUids.size !== 1 || !itemUids.has(provenUid)))) {
    throw new HttpError(422, "gacha_url_unverified", "抽卡 URL 可用，但无法确认 UID");
  }
  const items = (payload.data?.list ?? []).map((item) => normalize(provenUid, item));
  if (!items.length) throw new HttpError(422, "gacha_url_unverified", "抽卡 URL 可用，但无法确认 UID");
  return { uid: provenUid, items };
}

export async function issue(uid: string, initialize?: (client: PoolClient) => Promise<void>): Promise<{ uid: string; token: string; token_ref: string; reverified_at: string }> {
  const token = randomBytes(32).toString("base64url"), reverifiedAt = new Date().toISOString();
  await transaction(async (client) => {
    await client.query("INSERT INTO users(uid) VALUES($1) ON CONFLICT(uid) DO UPDATE SET updated_at=now()", [uid]);
    await client.query(`INSERT INTO sessions(token_hash,uid,reverified_at,expires_at,last_seen_at)
      VALUES($1,$2,$3,now()+interval '30 days',now())`, [hash(token), uid, reverifiedAt]);
    await initialize?.(client);
  });
  return { uid, token, token_ref: `keychain:cloud:${uid}`, reverified_at: reverifiedAt };
}

export async function reverify(token: string, uid: string): Promise<{ uid: string; token: string; token_ref: string; reverified_at: string }> {
  const session = await requireSession(token);
  if (session.uid !== uid) throw new HttpError(403, "identity_mismatch", "抽卡 URL 与云端会话 UID 不一致");
  const rotated = randomBytes(32).toString("base64url"), reverifiedAt = new Date().toISOString();
  const result = await pool().query(`UPDATE sessions SET token_hash=$1,reverified_at=$2,last_seen_at=now()
    WHERE token_hash=$3 AND uid=$4 AND revoked_at IS NULL AND expires_at>now()
    AND last_seen_at>now()-interval '7 days' RETURNING uid`, [hash(rotated), reverifiedAt, hash(token), uid]);
  if (!result.rowCount) throw new HttpError(401, "unauthorized", "云端会话无效");
  return { uid, token: rotated, token_ref: `keychain:cloud:${uid}`, reverified_at: reverifiedAt };
}

export async function requireSession(token: string, uid?: string): Promise<{ uid: string; reverified_at: string }> {
  const digest = hash(token), result = await pool().query(`UPDATE sessions SET last_seen_at=now() WHERE token_hash=$1
    AND revoked_at IS NULL AND expires_at>now() AND last_seen_at>now()-interval '7 days'
    AND ($2::text IS NULL OR uid=$2) RETURNING uid,reverified_at`, [digest, uid ?? null]);
  const session = result.rows[0] as { uid: string; reverified_at: Date } | undefined;
  if (!session) throw new HttpError(401, "unauthorized", "云端会话无效");
  return { uid: session.uid, reverified_at: session.reverified_at.toISOString() };
}

export async function requireFresh(token: string): Promise<{ uid: string }> {
  const session = await requireSession(token);
  if (Date.now() - Date.parse(session.reverified_at) > 24 * 60 * 60 * 1000) throw new HttpError(428, "reverify_required", "请重新验证抽卡 URL");
  return { uid: session.uid };
}

export async function revoke(token: string): Promise<void> {
  await requireSession(token);
  await pool().query("UPDATE sessions SET revoked_at=now() WHERE token_hash=$1", [hash(token)]);
}

function hash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function normalize(uid: string, item: Record<string, any>): GachaItem {
  const type = String(item.gacha_type);
  const rawTime = String(item.time).replace(" ", "T"), epoch = Date.parse(`${rawTime}+08:00`);
  if (!Number.isFinite(epoch)) throw new HttpError(422, "gacha_item_invalid", "抽卡记录时间无效");
  return { id: String(item.id), uid, gacha_type: type, uigf_gacha_type: type === "400" ? "301" : type,
    item_id: String(item.item_id), name: String(item.name), item_type: String(item.item_type),
    rank: Number(item.rank_type ?? item.rank), time: new Date(epoch).toISOString() };
}

export function equalToken(a: string, b: string): boolean {
  const left = Buffer.from(a), right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
