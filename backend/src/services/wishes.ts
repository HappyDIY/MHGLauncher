import type { Store } from "../core/database";
import type { GameRole, WishRecord, WishStatistics } from "../core/models";
import type { Provider } from "../providers/provider";
import type { ImageCache } from "./images";
import { enrich } from "./metadata";
import { banner, type BannerDetail } from "./wish-statistics";

const wish = (row: Record<string, unknown>): WishRecord => ({
  id: String(row.id), uid: String(row.uid), gacha_type: String(row.gacha_type),
  uigf_gacha_type: String(row.uigf_gacha_type || (row.gacha_type === "400" ? "301" : row.gacha_type)),
  item_id: String(row.item_id), name: String(row.name), item_type: String(row.item_type),
  rank: Number(row.rank), time: String(row.time),
});

export class WishService {
  constructor(private readonly store: Store, private readonly provider: Provider, private readonly images: ImageCache) {}

  async sync(credential: string, role: GameRole, log?: (message: string) => void): Promise<number> {
    const newest = Object.fromEntries(this.store.all(`SELECT COALESCE(NULLIF(uigf_gacha_type,''),gacha_type) gacha_type,MAX(id) id
      FROM wishes WHERE uid=? GROUP BY COALESCE(NULLIF(uigf_gacha_type,''),gacha_type)`, role.uid)
      .map((row) => [String(row.gacha_type), String(row.id)]));
    log?.(`已读取 ${Object.keys(newest).length} 个卡池的本地增量检查点`);
    let inserted = 0, pages = 0;
    for await (const records of this.provider.wishes(credential, role, newest)) {
      const before = this.count(role.uid); this.save(records); const added = this.count(role.uid) - before;
      inserted += added; pages += 1; log?.(`第 ${pages} 页读取 ${records.length} 条记录，新增 ${added} 条`);
    }
    log?.(`米游社分页读取完成，共处理 ${pages} 页`);
    return inserted;
  }

  save(records: WishRecord[]): void {
    const insert = this.store.db.prepare(`INSERT INTO wishes(id,uid,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time)
      VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
      uigf_gacha_type=COALESCE(NULLIF(excluded.uigf_gacha_type,''),wishes.uigf_gacha_type),
      name=COALESCE(NULLIF(excluded.name,''),wishes.name),item_type=COALESCE(NULLIF(excluded.item_type,''),wishes.item_type),
      rank=CASE WHEN excluded.rank>0 THEN excluded.rank ELSE wishes.rank END`);
    this.store.db.transaction(() => records.forEach((value) => insert.run(
      value.id, value.uid, value.gacha_type, value.uigf_gacha_type, value.item_id,
      value.name, value.item_type, value.rank, value.time,
    )))();
  }

  clear(): number { return this.store.db.prepare("DELETE FROM wishes").run().changes; }

  list(uid: string, type?: string): WishRecord[] {
    const rows = type
      ? this.store.all("SELECT * FROM wishes WHERE uid=? AND gacha_type=? ORDER BY time DESC,id DESC", uid, type)
      : this.store.all("SELECT * FROM wishes WHERE uid=? ORDER BY time DESC,id DESC", uid);
    return rows.map(wish).map((value) => enrich(value, this.images));
  }

  statistics(uid: string): WishStatistics[] {
    const groups = Map.groupBy(this.list(uid), (value) => value.uigf_gacha_type);
    return [...groups.entries()].sort().map(([type, records]) => ({
      uid, gacha_type: type, total: records.length,
      five_star_count: records.filter(({ rank }) => rank === 5).length,
      pulls_since_five_star: records.findIndex(({ rank }) => rank === 5) < 0 ? records.length : records.findIndex(({ rank }) => rank === 5),
    }));
  }

  bannerStatistics(uid: string): BannerDetail[] {
    const records = this.store.all("SELECT * FROM wishes WHERE uid=? ORDER BY time ASC,id ASC", uid).map(wish);
    return [...Map.groupBy(records, (value) => value.uigf_gacha_type).entries()].sort()
      .map(([type, values]) => banner(uid, type, values, this.images));
  }

  private count(uid: string): number { return Number(this.store.one("SELECT COUNT(*) count FROM wishes WHERE uid=?", uid)?.count ?? 0); }
}
