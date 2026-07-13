import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { Store } from "../core/database";
import type { AchievementArchive, AchievementGoal, AchievementItem, AchievementSnapshot, AchievementViewItem } from "../core/models";

type UIAF = { info?: Record<string, unknown>; list?: { id: number; current?: number; status?: number; timestamp?: number }[] };
type Reward = { Count?: number };
type GoalMeta = { Id: number; Order: number; Name: string; FinishReward?: Reward; Icon: string };
type AchievementMeta = {
  Id: number; Goal: number; Order: number; Title: string; Description: string;
  FinishReward?: Reward; Progress: number; Version: string; Icon?: string; IsDailyQuest?: boolean;
};
let achievementCache: AchievementMeta[] | undefined;
let goalCache: GoalMeta[] | undefined;

const archive = (row: Record<string, unknown>): AchievementArchive => ({
  id: String(row.id), name: String(row.name), selected: Boolean(row.selected),
  created_at: String(row.created_at), updated_at: String(row.updated_at), revision: Number(row.revision ?? 0),
});
const item = (row: Record<string, unknown>): AchievementItem => ({
  archive_id: String(row.archive_id), achievement_id: Number(row.achievement_id),
  current: Number(row.current), status: Number(row.status), timestamp: Number(row.timestamp),
  updated_at: String(row.updated_at),
});
const icon = (name?: string): string | null => name ? `https://api.snaphutaorp.org/static/raw/AchievementIcon/${name}.png` : null;
const achievementMeta = (): AchievementMeta[] => {
  achievementCache ??= JSON.parse(readFileSync(join(process.cwd(), "src/mhglauncher/data/achievement.json"), "utf8")) as AchievementMeta[];
  return achievementCache;
};
const goalMeta = (): GoalMeta[] => {
  goalCache ??= JSON.parse(readFileSync(join(process.cwd(), "src/mhglauncher/data/achievement_goals.json"), "utf8")) as GoalMeta[];
  return goalCache;
};

export class AchievementService {
  constructor(private readonly store: Store) {}

  archives(): AchievementArchive[] {
    return this.store.all("SELECT * FROM achievement_archives ORDER BY selected DESC,updated_at DESC").map(archive);
  }

  createArchive(name: string): AchievementArchive {
    if (!name.trim()) throw new AppError("archive_name_invalid", "成就档案名称不能为空", 422);
    const now = new Date().toISOString(), id = randomUUID();
    this.store.db.transaction(() => {
      if (!this.archives().length) this.store.db.exec("UPDATE achievement_archives SET selected=0");
      this.store.db.prepare("INSERT INTO achievement_archives(id,name,selected,created_at,updated_at,revision) VALUES(?,?,?,?,?,0)")
        .run(id, name.trim(), Number(!this.archives().length), now, now);
    })();
    return { id, name: name.trim(), selected: !this.archives().some((value) => value.id !== id), created_at: now, updated_at: now };
  }

  selectArchive(id: string): AchievementArchive {
    const value = this.store.one("SELECT * FROM achievement_archives WHERE id=?", id);
    if (!value) throw new AppError("archive_missing", "成就档案不存在", 404);
    this.store.db.transaction(() => {
      this.store.db.exec("UPDATE achievement_archives SET selected=0");
      this.store.db.prepare("UPDATE achievement_archives SET selected=1,updated_at=? WHERE id=?").run(new Date().toISOString(), id);
    })();
    return { ...archive(value), selected: true };
  }

  removeArchive(id: string): number {
    return this.store.db.prepare("DELETE FROM achievement_archives WHERE id=?").run(id).changes;
  }

  list(archiveId = this.selectedId()): AchievementItem[] {
    return archiveId ? this.store.all("SELECT * FROM achievements WHERE archive_id=? ORDER BY achievement_id", archiveId).map(item) : [];
  }

  goals(): AchievementGoal[] {
    return goalMeta().map((value) => ({
      id: value.Id, order: value.Order, name: value.Name,
      reward_count: value.FinishReward?.Count ?? 0, icon_url: icon(value.Icon),
    }));
  }

  view(archiveId = this.selectedId()): AchievementViewItem[] {
    const existing = new Map(this.list(archiveId).map((value) => [value.achievement_id, value]));
    return achievementMeta().map((meta) => {
      const saved = existing.get(meta.Id);
      return {
        archive_id: archiveId ?? "", achievement_id: meta.Id, current: saved?.current ?? 0,
        status: saved?.status ?? 0, timestamp: saved?.timestamp ?? 0, updated_at: saved?.updated_at ?? "",
        goal: meta.Goal, order: meta.Order, title: meta.Title, description: meta.Description,
        progress: meta.Progress, version: meta.Version, reward_count: meta.FinishReward?.Count ?? 0,
        icon_url: icon(meta.Icon), is_daily_quest: Boolean(meta.IsDailyQuest),
      };
    });
  }

  snapshot(archiveId: string): AchievementSnapshot {
    const row = this.store.one("SELECT * FROM achievement_archives WHERE id=?", archiveId);
    if (!row) throw new AppError("archive_missing", "成就档案不存在", 404);
    const selected = archive(row);
    return { archive: selected, entries: this.view(archiveId), revision: selected.revision ?? 0 };
  }

  saveSnapshot(
    archiveId: string, expectedRevision: number,
    values: Omit<AchievementItem, "archive_id" | "updated_at">[],
  ): AchievementSnapshot {
    this.store.db.transaction(() => {
      const current = Number(this.store.one("SELECT revision FROM achievement_archives WHERE id=?", archiveId)?.revision ?? -1);
      if (current < 0) throw new AppError("archive_missing", "成就档案不存在", 404);
      if (current !== expectedRevision) throw new AppError("archive_revision_conflict", "成就档案已被其他操作更新", 409);
      this.writeItems(archiveId, values);
      this.store.db.prepare("UPDATE achievement_archives SET revision=revision+1,updated_at=? WHERE id=?")
        .run(new Date().toISOString(), archiveId);
    })();
    return this.snapshot(archiveId);
  }

  save(archiveId: string, values: Omit<AchievementItem, "archive_id" | "updated_at">[]): AchievementItem[] {
    this.requireArchive(archiveId);
    this.store.db.transaction(() => this.writeItems(archiveId, values))();
    return this.list(archiveId);
  }

  private writeItems(archiveId: string, values: Omit<AchievementItem, "archive_id" | "updated_at">[]): void {
    const now = new Date().toISOString();
    const insert = this.store.db.prepare(`INSERT INTO achievements(archive_id,achievement_id,current,status,timestamp,updated_at)
      VALUES(?,?,?,?,?,?) ON CONFLICT(archive_id,achievement_id) DO UPDATE SET
      current=excluded.current,status=excluded.status,timestamp=excluded.timestamp,updated_at=excluded.updated_at`);
    values.forEach((value) => insert.run(
      archiveId, value.achievement_id, value.current, value.status, value.timestamp, now,
    ));
  }

  importUIAF(archiveId: string, expectedRevision: number, payload: UIAF): AchievementSnapshot {
    const values = (payload.list ?? []).map((value) => ({
      achievement_id: Number(value.id), current: Number(value.current ?? 0),
      status: Number(value.status ?? 0), timestamp: Number(value.timestamp ?? 0),
    })).filter((value) => value.achievement_id > 0);
    return this.saveSnapshot(archiveId, expectedRevision, values);
  }

  exportUIAF(archiveId = this.selectedId()): Record<string, unknown> {
    if (!archiveId) return { info: { export_app: "MHGLauncher", uiaf_version: "v1.1" }, list: [] };
    return { info: { export_app: "MHGLauncher", uiaf_version: "v1.1", export_timestamp: Math.floor(Date.now() / 1000) },
      list: this.list(archiveId).map((value) => ({ id: value.achievement_id, current: value.current, status: value.status, timestamp: value.timestamp })) };
  }

  selectedId(): string | undefined {
    return this.store.one("SELECT id FROM achievement_archives ORDER BY selected DESC,updated_at DESC LIMIT 1")?.id as string | undefined;
  }

  private requireArchive(id: string): void {
    if (!this.store.one("SELECT id FROM achievement_archives WHERE id=?", id)) throw new AppError("archive_missing", "成就档案不存在", 404);
  }
}
