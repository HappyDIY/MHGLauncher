import type { Store } from "../core/database";
import type { CompanionSnapshot, GameRole, WishRecord, WishStatistics } from "../core/models";
import type { Provider } from "../providers/provider";
import type { GameRecordSource } from "../providers/game-record";
import type { ImageCache } from "./images";
import { enrich } from "./metadata";
import { banner, type BannerDetail } from "./wish-statistics";
import { AppError } from "../core/errors";

const wish = (row: Record<string, unknown>): WishRecord => ({
  id: String(row.id), uid: String(row.uid), gacha_type: String(row.gacha_type),
  uigf_gacha_type: String(row.uigf_gacha_type || (row.gacha_type === "400" ? "301" : row.gacha_type)),
  item_id: String(row.item_id), name: String(row.name), item_type: String(row.item_type),
  rank: Number(row.rank), time: String(row.time),
});

export class WishService {
  constructor(
    private readonly store: Store, private readonly provider: Provider,
    private readonly images: ImageCache, private readonly gachaRecords?: GameRecordSource,
  ) {}

  async sync(credential: string, role: GameRole, log?: (message: string) => void): Promise<number> {
    const newest = Object.fromEntries(this.store.all(`SELECT gacha_type,id FROM (
      SELECT COALESCE(NULLIF(uigf_gacha_type,''),gacha_type) gacha_type,id,
      ROW_NUMBER() OVER(PARTITION BY COALESCE(NULLIF(uigf_gacha_type,''),gacha_type) ORDER BY LENGTH(id) DESC,id DESC) row_number
      FROM wishes WHERE uid=?) WHERE row_number=1`, role.uid)
      .map((row) => [String(row.gacha_type), String(row.id)]));
    log?.(`已读取 ${Object.keys(newest).length} 个卡池的本地增量检查点`);
    let inserted = 0, pages = 0;
    for await (const records of this.provider.wishes(credential, role, newest)) {
      const added = this.newRecordCount(records); this.save(records);
      inserted += added; pages += 1; log?.(`第 ${pages} 页读取 ${records.length} 条记录，新增 ${added} 条`);
    }
    log?.(`米游社分页读取完成，共处理 ${pages} 页`);
    return inserted;
  }

  async importFromGachaUrl(url: string, log?: (message: string) => void): Promise<{ inserted: number; uids: string[] }> {
    if (!this.gachaRecords) throw new AppError("gacha_import_unavailable", "当前环境不支持抽卡 URL 导入", 503);
    let inserted = 0, pages = 0;
    const uids = new Set<string>();
    for await (const records of this.gachaRecords.wishesFromGachaUrl(url)) {
      records.forEach(({ uid }) => uids.add(uid));
      if (uids.size > 1) throw new AppError("gacha_uid_mismatch", "抽卡 URL 返回了不一致的 UID", 422);
      const added = this.newRecordCount(records); this.save(records);
      inserted += added; pages += 1; log?.(`第 ${pages} 个卡池读取 ${records.length} 条记录，新增 ${added} 条`);
    }
    log?.(`抽卡 URL 分页读取完成，共处理 ${pages} 个卡池`);
    return { inserted, uids: [...uids] };
  }

  save(records: WishRecord[]): void {
    if (!records.length) return;
    const insert = this.store.db.prepare(`INSERT INTO wishes(id,uid,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,time_epoch)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,id) DO UPDATE SET
      uigf_gacha_type=COALESCE(NULLIF(excluded.uigf_gacha_type,''),wishes.uigf_gacha_type),
      name=COALESCE(NULLIF(excluded.name,''),wishes.name),item_type=COALESCE(NULLIF(excluded.item_type,''),wishes.item_type),
      rank=CASE WHEN excluded.rank>0 THEN excluded.rank ELSE wishes.rank END`);
    this.store.db.transaction(() => records.forEach((value) => {
      const time = normalizeTime(value.time);
      if (!time) throw new AppError("wish_time_invalid", "祈愿时间格式无效", 422);
      insert.run(value.id, value.uid, value.gacha_type, value.uigf_gacha_type, value.item_id,
        value.name, value.item_type, value.rank, time.iso, time.epoch);
    }))();
  }

  clear(): number { return this.store.db.prepare("DELETE FROM wishes").run().changes; }

  list(uid: string, type?: string): WishRecord[] {
    const rows = type
      ? this.store.all("SELECT * FROM wishes WHERE uid=? AND gacha_type=? ORDER BY time_epoch DESC,LENGTH(id) DESC,id DESC", uid, type)
      : this.store.all("SELECT * FROM wishes WHERE uid=? ORDER BY time_epoch DESC,LENGTH(id) DESC,id DESC", uid);
    return rows.map(wish).map((value) => enrich(value, this.images));
  }

  statistics(uid: string): WishStatistics[] {
    const rows = this.store.all(`SELECT uid,COALESCE(NULLIF(uigf_gacha_type,''),gacha_type) uigf_gacha_type,rank
      FROM wishes WHERE uid=? ORDER BY time_epoch DESC,LENGTH(id) DESC,id DESC`, uid);
    return this.statisticsFrom(rows.map((row) => ({
      id: "", uid: String(row.uid), gacha_type: String(row.uigf_gacha_type),
      uigf_gacha_type: String(row.uigf_gacha_type), item_id: "", name: "", item_type: "",
      rank: Number(row.rank), time: "",
    })));
  }

  snapshot(uid: string, note: unknown): CompanionSnapshot {
    const wishes = this.list(uid), ascending = [...wishes].reverse();
    return {
      wishes, statistics: this.statisticsFrom(wishes),
      banner_statistics: [...Map.groupBy(ascending, (value) => value.uigf_gacha_type).entries()]
        .sort().map(([type, values]) => banner(uid, type, values, this.images)),
      note: note as CompanionSnapshot["note"],
    };
  }

  private statisticsFrom(records: WishRecord[]): WishStatistics[] {
    const groups = Map.groupBy(records, (value) => value.uigf_gacha_type);
    return [...groups.entries()].sort().map(([type, records]) => ({
      uid: records[0]?.uid ?? "", gacha_type: type, total: records.length,
      five_star_count: records.filter(({ rank }) => rank === 5).length,
      pulls_since_five_star: records.findIndex(({ rank }) => rank === 5) < 0 ? records.length : records.findIndex(({ rank }) => rank === 5),
    }));
  }

  bannerStatistics(uid: string): BannerDetail[] {
    const records = this.store.all("SELECT * FROM wishes WHERE uid=? ORDER BY time_epoch ASC,LENGTH(id) ASC,id ASC", uid).map(wish);
    return [...Map.groupBy(records, (value) => value.uigf_gacha_type).entries()].sort()
      .map(([type, values]) => banner(uid, type, values, this.images));
  }

  private newRecordCount(records: WishRecord[]): number {
    const ids = [...new Set(records.map(({ id }) => id))];
    if (!ids.length) return 0;
    const placeholders = ids.map(() => "?").join(",");
    const uid = records[0]?.uid ?? "";
    const existing = new Set(this.store.all(`SELECT id FROM wishes WHERE uid=? AND id IN (${placeholders})`, uid, ...ids).map(({ id }) => String(id)));
    return ids.filter((id) => !existing.has(id)).length;
  }
}

function normalizeTime(value: string): { iso: string; epoch: number } | null {
  const explicit = /(Z|[+-]\d{2}:\d{2})$/i.test(value) ? value : `${value.replace(" ", "T")}+08:00`;
  const epoch = Date.parse(explicit);
  return Number.isFinite(epoch) ? { iso: new Date(epoch).toISOString(), epoch } : null;
}
