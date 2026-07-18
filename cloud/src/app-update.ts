import { z } from "zod";
import { HttpError } from "./http";
import { pool, ready } from "./db";

const version = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
export const appUpdateSchema = z.object({
  version: z.string().regex(version),
  download_url: z.string().url().max(2_048),
  sha256: z.string().regex(/^[a-fA-F0-9]{64}$/),
  size: z.coerce.number().int().positive().max(4 * 1024 * 1024 * 1024),
  changelog: z.string().min(1).max(20_000),
}).strict().superRefine((value, context) => {
  const url = new URL(value.download_url);
  if (url.protocol !== "https:" || url.username || url.password) {
    context.addIssue({ code: "custom", path: ["download_url"], message: "更新地址必须使用无凭据的 HTTPS URL" });
  }
  if (!/\.(?:dmg|pkg|zip)$/i.test(url.pathname)) {
    context.addIssue({ code: "custom", path: ["download_url"], message: "更新包格式不受支持" });
  }
});

export type AppUpdate = z.infer<typeof appUpdateSchema>;

export function latestUpdate(env: NodeJS.ProcessEnv = process.env): AppUpdate {
  const result = appUpdateSchema.safeParse({
    version: env.MHG_UPDATE_VERSION,
    download_url: env.MHG_UPDATE_DOWNLOAD_URL,
    sha256: env.MHG_UPDATE_SHA256,
    size: env.MHG_UPDATE_SIZE,
    changelog: env.MHG_UPDATE_CHANGELOG,
  });
  if (!result.success) {
    throw new HttpError(503, "update_not_configured", "应用更新信息尚未配置");
  }
  return { ...result.data, sha256: result.data.sha256.toLowerCase() };
}

export async function currentUpdate(env: NodeJS.ProcessEnv = process.env): Promise<AppUpdate & { source: "database" | "environment" }> {
  if (!env.DATABASE_URL) return { ...latestUpdate(env), source: "environment" };
  await ready();
  const result = await pool().query("SELECT version,download_url,sha256,size,changelog FROM app_releases WHERE status='published' LIMIT 1");
  const row = result.rows[0];
  if (row) return { ...appUpdateSchema.parse({ ...row, size: Number(row.size) }), sha256: String(row.sha256).toLowerCase(), source: "database" };
  return { ...latestUpdate(env), source: "environment" };
}
