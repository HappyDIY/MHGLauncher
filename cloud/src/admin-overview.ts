import { pool } from "./db";

export async function overview() {
  const [counts, release, audits] = await Promise.all([
    pool().query(`SELECT (SELECT COUNT(*) FROM users) users,
      (SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL AND expires_at>now() AND last_seen_at>now()-interval '7 days') active_sessions,
      (SELECT COUNT(*) FROM gacha_records) gacha_records,
      (SELECT COUNT(*) FROM achievement_archives) achievement_archives`),
    pool().query("SELECT version,published_at FROM app_releases WHERE status='published' LIMIT 1"),
    pool().query(`SELECT id,actor,action,target_type,target_ref,result,created_at FROM admin_audit_events
      ORDER BY created_at DESC,id DESC LIMIT 8`),
  ]);
  const totals = counts.rows[0];
  let currentRelease: { version: string; source: string; published_at: string | null } | null = null;
  if (release.rows[0]) currentRelease = { version: String(release.rows[0].version), source: "database", published_at: release.rows[0].published_at.toISOString() };
  else if (process.env.MHG_UPDATE_VERSION) currentRelease = { version: process.env.MHG_UPDATE_VERSION, source: "environment", published_at: null };
  return { healthy: true, database: "connected", totals: Object.fromEntries(Object.entries(totals).map(([key, value]) => [key, Number(value)])),
    current_release: currentRelease, recent_audit: audits.rows.map((row) => ({ ...row, id: Number(row.id), created_at: row.created_at.toISOString() })) };
}

export async function listAudit(cursor: number | undefined, limit: number) {
  const result = await pool().query(`SELECT id,actor,action,target_type,target_ref,result,metadata,created_at
    FROM admin_audit_events WHERE id<$1 ORDER BY id DESC LIMIT $2`, [cursor ?? Number.MAX_SAFE_INTEGER, limit + 1]);
  const items = result.rows.slice(0, limit).map((row) => ({ ...row, id: Number(row.id), created_at: row.created_at.toISOString() }));
  return { items, next_cursor: result.rows.length > limit ? items.at(-1)?.id ?? null : null };
}
