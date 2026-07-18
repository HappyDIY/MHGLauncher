import { appUpdateSchema, latestUpdate } from "./app-update";
import { pool, transaction } from "./db";
import { HttpError } from "./http";
import type { AdminContext } from "./admin-auth";
import { audit } from "./admin-audit";

export async function listReleases() {
  const result = await pool().query(`SELECT id,version,download_url,sha256,size,changelog,status,created_at,published_at
    FROM app_releases ORDER BY created_at DESC,id DESC LIMIT 100`);
  const items = result.rows.map(releaseRow);
  if (!items.some((item) => item.status === "published")) {
    try { return { items, environment_fallback: latestUpdate() }; } catch { return { items, environment_fallback: null }; }
  }
  return { items, environment_fallback: null };
}

export async function createRelease(input: unknown, context: AdminContext) {
  const value = appUpdateSchema.parse(input);
  return transaction(async (client) => {
    const result = await client.query(`INSERT INTO app_releases(version,download_url,sha256,size,changelog)
      VALUES($1,$2,$3,$4,$5) RETURNING *`, [value.version, value.download_url, value.sha256.toLowerCase(), value.size, value.changelog]);
    await audit(context, "release.create", "release", value.version, {}, client);
    return releaseRow(result.rows[0]);
  }).catch((error: { code?: string }) => {
    if (error.code === "23505") throw new HttpError(409, "release_exists", "该版本已经存在");
    throw error;
  });
}

export async function publishRelease(id: number, context: AdminContext, action = "release.publish") {
  return transaction(async (client) => {
    const existing = await client.query("SELECT version FROM app_releases WHERE id=$1", [id]);
    if (!existing.rowCount) throw new HttpError(404, "release_not_found", "版本不存在");
    await client.query("UPDATE app_releases SET status='archived' WHERE status='published'");
    const result = await client.query(`UPDATE app_releases SET status='published',published_at=now() WHERE id=$1 RETURNING *`, [id]);
    await audit(context, action, "release", String(existing.rows[0].version), {}, client);
    return releaseRow(result.rows[0]);
  });
}

function releaseRow(row: Record<string, any>) {
  return { id: Number(row.id), version: String(row.version), download_url: String(row.download_url),
    sha256: String(row.sha256), size: Number(row.size), changelog: String(row.changelog), status: String(row.status),
    created_at: row.created_at.toISOString(), published_at: row.published_at?.toISOString?.() ?? null };
}
