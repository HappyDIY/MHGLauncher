import type { PoolClient } from "pg";
import { pool, transaction } from "./db";
import { z } from "zod";
import { HttpError } from "./http";

export const cloudWishSchema = z.object({
  id: z.string().regex(/^\d{1,19}$/), uid: z.string().regex(/^\d{9,10}$/),
  gacha_type: z.enum(["100", "200", "301", "302", "400", "500"]),
  uigf_gacha_type: z.enum(["100", "200", "301", "302", "500"]), item_id: z.string().regex(/^\d{1,19}$/),
  name: z.string().max(128), item_type: z.string().max(64), rank: z.number().int().min(1).max(5),
  time: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/).refine((value) => Number.isFinite(Date.parse(value))),
}).strict();
export type CloudWish = z.infer<typeof cloudWishSchema>;

export async function upload(uid: string, items: unknown[]): Promise<{ uploaded: number }> {
  return transaction((client) => uploadWithClient(client, uid, items));
}

export async function uploadWithClient(client: PoolClient, uid: string, items: unknown[]): Promise<{ uploaded: number }> {
  const unique = new Map<string, CloudWish>();
  let parsed: CloudWish[]; try { parsed = z.array(cloudWishSchema).max(20_000).parse(items); }
  catch { throw new HttpError(422, "gacha_items_invalid", "抽卡记录格式无效"); }
  for (const item of parsed) if (item.uid === uid) unique.set(item.id, item);
  const filtered = [...unique.values()].sort((left, right) => left.id.length - right.id.length || left.id.localeCompare(right.id));
  for (const item of filtered) {
    await client.query(`INSERT INTO gacha_records(uid,id,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,payload)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(uid,id) DO UPDATE SET
      gacha_type=excluded.gacha_type,uigf_gacha_type=excluded.uigf_gacha_type,item_id=excluded.item_id,
      name=excluded.name,item_type=excluded.item_type,rank=excluded.rank,time=excluded.time,payload=excluded.payload`,
    [uid, item.id, item.gacha_type, item.uigf_gacha_type || item.gacha_type, item.item_id, item.name, item.item_type, item.rank, item.time, item]);
  }
  return { uploaded: filtered.length };
}

export async function retrieve(uid: string): Promise<{ items: CloudWish[] }> {
  const result = await pool().query("SELECT payload FROM gacha_records WHERE uid=$1 ORDER BY time DESC,LENGTH(id) DESC,id DESC", [uid]);
  try { return { items: z.array(cloudWishSchema).max(20_000).parse(result.rows.map((row) => row.payload)) }; }
  catch { throw new HttpError(500, "stored_data_invalid", "云端记录格式无效"); }
}

export async function endIds(uid: string): Promise<Record<string, string>> {
  const result = await pool().query(`SELECT DISTINCT ON (uigf_gacha_type) uigf_gacha_type,id FROM gacha_records
    WHERE uid=$1 ORDER BY uigf_gacha_type,LENGTH(id) DESC,id DESC`, [uid]);
  return Object.fromEntries(result.rows.map((row) => [String(row.uigf_gacha_type), String(row.id)]));
}

export async function entries(uid: string): Promise<{ uid: string; total: number; updated_at: string | null }[]> {
  const result = await pool().query("SELECT uid,COUNT(*) total,MAX(time) updated_at FROM gacha_records WHERE uid=$1 GROUP BY uid", [uid]);
  return result.rows.map((row) => ({ uid: String(row.uid), total: Number(row.total), updated_at: row.updated_at?.toISOString?.() ?? null }));
}

export async function remove(uid: string): Promise<{ deleted: number }> {
  const result = await pool().query("DELETE FROM gacha_records WHERE uid=$1", [uid]);
  return { deleted: result.rowCount ?? 0 };
}
