import type { Store } from "../core/database";
import type { DailyNote, GameState, NotificationEvent, NotificationSettings } from "../core/models";
import type { GachaResourceService } from "./gacha-resources";

const bool = (value: unknown): boolean => Boolean(Number(value));
const settings = (row: Record<string, unknown>): NotificationSettings => ({
  daily_commission_enabled: bool(row.daily_commission_enabled),
  daily_commission_time: String(row.daily_commission_time),
  resin_full_enabled: bool(row.resin_full_enabled),
  gacha_refresh_enabled: bool(row.gacha_refresh_enabled),
  version_update_enabled: bool(row.version_update_enabled),
});

export class NotificationService {
  constructor(
    private readonly store: Store,
    private readonly gachaResources: GachaResourceService,
    private readonly clock: () => Date = () => new Date(),
  ) {}

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
    const now = this.clock(), config = this.get(), events: NotificationEvent[] = [];
    this.evaluateDaily(events, note, config, now);
    this.evaluateResin(events, note, config);
    this.evaluateGacha(events, config, now);
    if (config.version_update_enabled && game?.status === "update_available") {
      this.add(events, `version:${game.available_version}`, "游戏版本更新可用", `可更新到 ${game.available_version}`, "game");
    }
    return events;
  }

  acknowledge(keys: string[]): string[] {
    const createdAt = this.clock().toISOString();
    const insert = this.store.db.prepare(
      "INSERT OR IGNORE INTO notification_state(key,last_triggered_at,state) VALUES(?,?,?)",
    );
    const transaction = this.store.db.transaction((values: string[]) => {
      for (const key of values) insert.run(key, createdAt, "{}");
    });
    transaction(keys);
    return keys;
  }

  private evaluateDaily(
    events: NotificationEvent[], note: DailyNote | null, config: NotificationSettings, now: Date,
  ): void {
    if (!note) return;
    const key = `daily:${note.uid}:${this.chinaDay(now)}`;
    this.removeOther("daily", note.uid, key);
    if (config.daily_commission_enabled && !note.extra_task_reward_received
      && this.after(config.daily_commission_time, now)) {
      this.add(events, key, "每日委托奖励尚未领取", `UID ${note.uid} 还有每日委托奖励未领取`, "notes");
    }
  }

  private evaluateResin(
    events: NotificationEvent[], note: DailyNote | null, config: NotificationSettings,
  ): void {
    if (!note) return;
    const key = `resin:${note.uid}:${note.max_resin}`;
    if (!config.resin_full_enabled || note.current_resin < note.max_resin) {
      this.store.db.prepare("DELETE FROM notification_state WHERE key=?").run(key);
      return;
    }
    this.add(events, key, "体力已回满", `UID ${note.uid} 当前体力 ${note.current_resin}/${note.max_resin}`, "notes");
  }

  private evaluateGacha(
    events: NotificationEvent[], config: NotificationSettings, now: Date,
  ): void {
    if (!config.gacha_refresh_enabled) return;
    const started = this.latestActiveGachaStart(now);
    if (!started) return;
    const key = `gacha:${started.getTime()}`;
    this.removeOther("gacha", null, key);
    this.add(events, key, "卡池已刷新", "新的活动祈愿已经开放", "gachaHistory");
  }

  private add(
    events: NotificationEvent[], key: string, title: string, body: string, destination: string,
  ): void {
    if (this.store.one("SELECT key FROM notification_state WHERE key=?", key)) return;
    events.push({ key, title, body, destination, created_at: this.clock().toISOString() });
  }

  private latestActiveGachaStart(now: Date): Date | null {
    try {
      const starts = this.gachaResources.events().flatMap(({ started_at, ended_at }) => {
        if (!started_at) return [];
        const start = new Date(started_at);
        const end = ended_at ? new Date(ended_at) : null;
        const active = !Number.isNaN(start.getTime()) && start <= now
          && (!end || Number.isNaN(end.getTime()) || end >= now);
        return active ? [start] : [];
      });
      return starts.sort((left, right) => right.getTime() - left.getTime())[0] ?? null;
    } catch {
      return null;
    }
  }

  private after(value: string, now: Date): boolean {
    if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) return false;
    const [hour, minute] = value.split(":").map(Number);
    const parts = this.chinaParts(now);
    return parts.hour > hour! || (parts.hour === hour && parts.minute >= minute!);
  }

  private chinaDay(date: Date): string {
    const { year, month, day } = this.chinaParts(date);
    return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  }

  private chinaParts(date: Date): Record<"year" | "month" | "day" | "hour" | "minute", number> {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", hourCycle: "h23",
    });
    const values = Object.fromEntries(formatter.formatToParts(date).map((part) => [part.type, Number(part.value)]));
    return values as Record<"year" | "month" | "day" | "hour" | "minute", number>;
  }

  private removeOther(kind: string, uid: string | null, current: string): void {
    const prefix = uid ? `${kind}:${uid}:%` : `${kind}:%`;
    this.store.db.prepare("DELETE FROM notification_state WHERE key LIKE ? AND key<>?").run(prefix, current);
  }
}
