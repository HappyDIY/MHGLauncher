import { pool } from "./db";
import { HttpError } from "./http";
import { z } from "zod";

export const cloudAchievementSchema = z.object({
  achievement_id: z.number().int().positive(), current: z.number().int().min(0),
  status: z.number().int().min(0).max(3), timestamp: z.number().int().min(0),
}).strict();
export type CloudAchievement = z.infer<typeof cloudAchievementSchema>;

export async function upload(uid: string, items: unknown[]): Promise<{ uploaded: number }> {
  let parsed: CloudAchievement[];
  try { parsed = z.array(cloudAchievementSchema).max(200_000).parse(items); }
  catch { throw new HttpError(422, "achievement_items_invalid", "成就记录格式无效"); }
  const unique = new Map(parsed.map((item) => [item.achievement_id, item]));
  const values = [...unique.values()].sort((left, right) => left.achievement_id - right.achievement_id);
  await pool().query(`INSERT INTO achievement_archives(uid,payload,updated_at) VALUES($1,$2,now())
    ON CONFLICT(uid) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at`, [uid, JSON.stringify(values)]);
  return { uploaded: values.length };
}

export async function retrieve(uid: string): Promise<{ items: CloudAchievement[] }> {
  const result = await pool().query("SELECT payload FROM achievement_archives WHERE uid=$1", [uid]);
  if (!result.rows[0]) return { items: [] };
  try { return { items: z.array(cloudAchievementSchema).max(200_000).parse(result.rows[0].payload) }; }
  catch { throw new HttpError(500, "stored_data_invalid", "云端成就格式无效"); }
}
