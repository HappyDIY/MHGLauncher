import type { Store } from "../core/database";
import type { GameRole, GachaEvent } from "../core/models";
import type { GameRecordSource } from "../providers/game-record";
import { bundledGachaEvents } from "./gacha-event-metadata";
import type { ImageCache } from "./images";
import { iconURLs } from "./metadata";

const event = (row: Record<string, unknown>): GachaEvent => ({
  id: String(row.id), version: String(row.version), gacha_type: String(row.gacha_type),
  name: String(row.name), started_at: String(row.started_at) || null, ended_at: String(row.ended_at) || null,
  orange_up: JSON.parse(String(row.orange_up)) as string[],
  purple_up: JSON.parse(String(row.purple_up)) as string[],
  banner_url: row.banner_url ? String(row.banner_url) : null, updated_at: String(row.updated_at),
});

export class GachaEventService {
  constructor(private readonly store: Store, private readonly records: GameRecordSource, private readonly images: ImageCache) {}

  list(): GachaEvent[] {
    const persisted = this.store.all("SELECT * FROM gacha_events").map(event);
    const merged = new Map(bundledGachaEvents().map((value) => [key(value), value]));
    for (const value of persisted) merged.set(key(value), value);
    return [...merged.values()].map((value) => ({
      ...value,
      orange_up_icons: iconURLs(value.orange_up, this.images),
      purple_up_icons: iconURLs(value.purple_up, this.images),
    })).sort((left, right) =>
      String(right.started_at).localeCompare(String(left.started_at)) || left.name.localeCompare(right.name));
  }

  async refresh(credential: string, role: GameRole): Promise<GachaEvent[]> {
    const values = await this.records.gachaEvents(credential, role);
    this.save(values);
    return this.list();
  }

  private save(values: GachaEvent[]): void {
    const insert = this.store.db.prepare(`INSERT INTO gacha_events(id,version,gacha_type,name,started_at,ended_at,orange_up,purple_up,banner_url,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
      version=excluded.version,gacha_type=excluded.gacha_type,name=excluded.name,started_at=excluded.started_at,
      ended_at=excluded.ended_at,orange_up=excluded.orange_up,purple_up=excluded.purple_up,banner_url=excluded.banner_url,updated_at=excluded.updated_at`);
    this.store.db.transaction(() => values.forEach((value) => insert.run(
      value.id, value.version, value.gacha_type, value.name, value.started_at ?? "", value.ended_at ?? "",
      JSON.stringify(value.orange_up), JSON.stringify(value.purple_up), value.banner_url ?? null, value.updated_at,
    )))();
  }
}

function key(value: GachaEvent): string {
  return `${value.gacha_type}:${value.started_at ?? ""}:${value.name}`;
}
