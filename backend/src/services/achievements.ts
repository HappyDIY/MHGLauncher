import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { Store } from "../core/database";
import type { AchievementArchive, AchievementItem } from "../core/models";

type UIAF = { info?: Record<string, unknown>; list?: { id: number; current?: number; status?: number; timestamp?: number }[] };

const archive = (row: Record<string, unknown>): AchievementArchive => ({
  id: String(row.id), name: String(row.name), selected: Boolean(row.selected),
  created_at: String(row.created_at), updated_at: String(row.updated_at),
});
const item = (row: Record<string, unknown>): AchievementItem => ({
  archive_id: String(row.archive_id), achievement_id: Number(row.achievement_id),
  current: Number(row.current), status: Number(row.status), timestamp: Number(row.timestamp),
  updated_at: String(row.updated_at),
});

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
      this.store.db.prepare("INSERT INTO achievement_archives(id,name,selected,created_at,updated_at) VALUES(?,?,?,?,?)")
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

  save(archiveId: string, values: Omit<AchievementItem, "archive_id" | "updated_at">[]): AchievementItem[] {
    this.requireArchive(archiveId);
    const now = new Date().toISOString();
    const insert = this.store.db.prepare(`INSERT INTO achievements(archive_id,achievement_id,current,status,timestamp,updated_at)
      VALUES(?,?,?,?,?,?) ON CONFLICT(archive_id,achievement_id) DO UPDATE SET
      current=excluded.current,status=excluded.status,timestamp=excluded.timestamp,updated_at=excluded.updated_at`);
    this.store.db.transaction(() => values.forEach((value) => insert.run(
      archiveId, value.achievement_id, value.current, value.status, value.timestamp, now,
    )))();
    return this.list(archiveId);
  }

  importUIAF(archiveId: string, payload: UIAF): AchievementItem[] {
    const values = (payload.list ?? []).map((value) => ({
      achievement_id: Number(value.id), current: Number(value.current ?? 0),
      status: Number(value.status ?? 0), timestamp: Number(value.timestamp ?? 0),
    })).filter((value) => value.achievement_id > 0);
    return this.save(archiveId, values);
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
