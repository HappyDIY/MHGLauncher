import { pool, transaction } from "./db";
import { HttpError } from "./http";
import type { AdminContext } from "./admin-auth";
import { audit, privateUid } from "./admin-audit";

export async function listUsers(query: string, cursor: string | undefined, limit: number) {
  const values: unknown[] = [query ? `${query}%` : "%", cursor ?? "", limit + 1];
  const result = await pool().query(`SELECT u.uid,u.created_at,u.updated_at,
    COUNT(DISTINCT s.token_hash) total_sessions,
    COUNT(DISTINCT s.token_hash) FILTER(WHERE s.revoked_at IS NULL AND s.expires_at>now() AND s.last_seen_at>now()-interval '7 days') active_sessions,
    COUNT(DISTINCT g.id) gacha_count,MAX(g.time) latest_gacha,a.updated_at achievement_updated_at,
    COALESCE(jsonb_array_length(a.payload),0) achievement_count
    FROM users u LEFT JOIN sessions s ON s.uid=u.uid LEFT JOIN gacha_records g ON g.uid=u.uid
    LEFT JOIN achievement_archives a ON a.uid=u.uid WHERE u.uid LIKE $1 AND u.uid>$2
    GROUP BY u.uid,a.updated_at,a.payload ORDER BY u.uid LIMIT $3`, values);
  const rows = result.rows.slice(0, limit).map(userRow);
  return { items: rows, next_cursor: result.rows.length > limit ? rows.at(-1)?.uid ?? null : null };
}

export async function revokeUserSessions(uid: string, context: AdminContext) {
  return transaction(async (client) => {
    await ensureUser(uid, client);
    const result = await client.query("UPDATE sessions SET revoked_at=now() WHERE uid=$1 AND revoked_at IS NULL", [uid]);
    await audit(context, "user.sessions.revoke", "user", uid, { revoked: result.rowCount ?? 0 }, client);
    return { revoked: result.rowCount ?? 0 };
  });
}

export async function deleteUser(uid: string, context: AdminContext) {
  return transaction(async (client) => {
    const counts = await client.query(`SELECT (SELECT COUNT(*) FROM sessions WHERE uid=$1) sessions,
      (SELECT COUNT(*) FROM gacha_records WHERE uid=$1) gacha_records,
      (SELECT COUNT(*) FROM achievement_archives WHERE uid=$1) achievement_archives`, [uid]);
    const result = await client.query("DELETE FROM users WHERE uid=$1", [uid]);
    if (!result.rowCount) throw new HttpError(404, "user_not_found", "用户不存在");
    const summary = Object.fromEntries(Object.entries(counts.rows[0]).map(([key, value]) => [key, Number(value)]));
    await audit(context, "user.delete", "user", privateUid(uid), summary, client);
    return { deleted: true, ...summary };
  });
}

async function ensureUser(uid: string, client: { query: (text: string, values?: unknown[]) => Promise<{ rowCount: number | null }> }) {
  if (!(await client.query("SELECT 1 FROM users WHERE uid=$1", [uid])).rowCount) throw new HttpError(404, "user_not_found", "用户不存在");
}

function userRow(row: Record<string, any>) {
  const date = (value: any) => value?.toISOString?.() ?? null;
  return { uid: String(row.uid), created_at: date(row.created_at), updated_at: date(row.updated_at),
    total_sessions: Number(row.total_sessions), active_sessions: Number(row.active_sessions), gacha_count: Number(row.gacha_count), latest_gacha: date(row.latest_gacha),
    achievement_count: Number(row.achievement_count), achievement_updated_at: date(row.achievement_updated_at) };
}
