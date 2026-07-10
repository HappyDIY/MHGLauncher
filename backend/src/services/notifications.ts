import type { Store } from "../core/database";
import type { DailyNote, GameState, NotificationEvent, NotificationSettings } from "../core/models";

const bool = (value: unknown): boolean => Boolean(Number(value));
const settings = (row: Record<string, unknown>): NotificationSettings => ({
  daily_commission_enabled: bool(row.daily_commission_enabled),
  daily_commission_time: String(row.daily_commission_time),
  resin_full_enabled: bool(row.resin_full_enabled),
  gacha_refresh_enabled: bool(row.gacha_refresh_enabled),
  version_update_enabled: bool(row.version_update_enabled),
});

export class NotificationService {
  constructor(private readonly store: Store) {}

  get(): NotificationSettings {
    return settings(this.store.one("SELECT * FROM notification_settings WHERE id=1") ?? {});
  }

  update(value: Partial<NotificationSettings>): NotificationSettings {
    const next = { ...this.get(), ...value };
    this.store.db.prepare(`UPDATE notification_settings SET daily_commission_enabled=?,daily_commission_time=?,resin_full_enabled=?,
      gacha_refresh_enabled=?,version_update_enabled=? WHERE id=1`)
      .run(Number(next.daily_commission_enabled), next.daily_commission_time, Number(next.resin_full_enabled),
        Number(next.gacha_refresh_enabled), Number(next.version_update_enabled));
    return next;
  }

  evaluate(note: DailyNote | null, game: GameState | null): NotificationEvent[] {
    const now = new Date(), config = this.get(), events: NotificationEvent[] = [];
    if (note && config.daily_commission_enabled && note.finished_tasks < note.total_tasks && this.after(config.daily_commission_time, now)) {
      events.push(this.once(`daily:${note.uid}:${this.day(now)}`, "每日委托尚未完成", `UID ${note.uid} 还有每日委托奖励未领取`, "notes"));
    }
    if (note && config.resin_full_enabled && note.current_resin >= note.max_resin) {
      events.push(this.once(`resin:${note.uid}:${note.max_resin}`, "体力已回满", `UID ${note.uid} 当前体力 ${note.current_resin}/${note.max_resin}`, "notes"));
    }
    if (config.gacha_refresh_enabled && this.hasEventStartingToday(now)) {
      events.push(this.once(`gacha:${this.day(now)}`, "卡池已刷新", "新的活动祈愿已经开放", "gachaHistory"));
    }
    if (config.version_update_enabled && game?.status === "update_available") {
      events.push(this.once(`version:${game.available_version}`, "游戏版本更新可用", `可更新到 ${game.available_version}`, "game"));
    }
    return events.filter(Boolean);
  }

  private once(key: string, title: string, body: string, destination: string): NotificationEvent {
    const createdAt = new Date().toISOString();
    const seen = this.store.one("SELECT key FROM notification_state WHERE key=?", key);
    if (seen) return null as unknown as NotificationEvent;
    this.store.db.prepare("INSERT INTO notification_state(key,last_triggered_at,state) VALUES(?,?,?)").run(key, createdAt, "{}");
    return { key, title, body, destination, created_at: createdAt };
  }

  private hasEventStartingToday(now: Date): boolean {
    const day = this.day(now);
    return this.store.all("SELECT id FROM gacha_events WHERE substr(started_at,1,10)=? LIMIT 1", day).length > 0;
  }

  private after(value: string, now: Date): boolean {
    const [hour = 20, minute = 0] = value.split(":").map(Number);
    const cn = new Date(now.getTime() + 8 * 60 * 60 * 1000);
    return cn.getUTCHours() > hour || (cn.getUTCHours() === hour && cn.getUTCMinutes() >= minute);
  }

  private day(date: Date): string { return date.toISOString().slice(0, 10); }
}
