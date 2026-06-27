import { pool, transaction } from "./db";
import { HttpError } from "./http";

export type CloudWish = {
  id: string; uid: string; gacha_type: string; uigf_gacha_type: string; item_id: string;
  name: string; item_type: string; rank: number; time: string;
};

export async function upload(uid: string, items: CloudWish[]): Promise<{ uploaded: number }> {
  const filtered = items.filter((item) => item.uid === uid && item.id);
  await transaction(async (client) => {
    for (const item of filtered) {
      await client.query(`INSERT INTO gacha_records(uid,id,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,payload)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(uid,id) DO UPDATE SET
        gacha_type=excluded.gacha_type,uigf_gacha_type=excluded.uigf_gacha_type,item_id=excluded.item_id,
        name=excluded.name,item_type=excluded.item_type,rank=excluded.rank,time=excluded.time,payload=excluded.payload`,
      [uid, item.id, item.gacha_type, item.uigf_gacha_type || item.gacha_type, item.item_id, item.name, item.item_type, item.rank, item.time, item]);
    }
  });
  return { uploaded: filtered.length };
}

export async function retrieve(uid: string): Promise<{ items: CloudWish[] }> {
  const result = await pool().query("SELECT payload FROM gacha_records WHERE uid=$1 ORDER BY time DESC,id DESC", [uid]);
  return { items: result.rows.map((row) => row.payload as CloudWish) };
}

export async function endIds(uid: string): Promise<Record<string, string>> {
  const result = await pool().query("SELECT uigf_gacha_type,MAX(id) id FROM gacha_records WHERE uid=$1 GROUP BY uigf_gacha_type", [uid]);
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

export async function uploadCycle(uid: string, kind: string, record: { schedule_id?: string; payload?: unknown }): Promise<{ uploaded: number }> {
  const scheduleId = record.schedule_id;
  if (!scheduleId) throw new HttpError(422, "schedule_id_missing", "周期记录缺少 schedule_id");
  await pool().query(`INSERT INTO cycle_records(uid,kind,schedule_id,payload) VALUES($1,$2,$3,$4)
    ON CONFLICT(uid,kind,schedule_id) DO UPDATE SET payload=excluded.payload,uploaded_at=now()`, [uid, kind, scheduleId, record]);
  return { uploaded: 1 };
}

export async function cycles(uid: string, kind: string): Promise<{ records: unknown[] }> {
  const result = await pool().query("SELECT payload FROM cycle_records WHERE uid=$1 AND kind=$2 ORDER BY schedule_id DESC", [uid, kind]);
  return { records: result.rows.map((row) => row.payload) };
}
