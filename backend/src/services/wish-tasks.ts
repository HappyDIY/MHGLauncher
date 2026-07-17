import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { WishTask } from "../core/models";
import type { AccountService } from "./accounts";
import { importUIGF } from "./uigf";
import type { WishService } from "./wishes";
import { RevisionNotifier } from "./revision-notifier";
import { pruneTerminal } from "./task-retention";

export class WishTasks {
  private readonly jobs = new Map<string, WishTask>();
  private readonly updatedAt = new Map<string, number>();
  private readonly notifier = new RevisionNotifier<WishTask>();
  constructor(private readonly accounts: AccountService, private readonly wishes: WishService) {}

  startSync(credential: string): WishTask {
    const job = this.create("sync");
    void this.run(job, async () => {
      this.append(job, "正在读取当前选择的游戏角色", null);
      const role = this.accounts.selectedRole();
      if (!role) throw new AppError("role_missing", "尚未选择原神角色", 409);
      this.append(job, `已选择角色 UID ${role.uid}`, undefined, true);
      const inserted = await this.wishes.sync(credential, role, (value) => this.append(job, value));
      return { result: { inserted }, message: `同步完成，新增 ${inserted} 条记录` };
    });
    return job;
  }

  startImport(payload: unknown): WishTask {
    const job = this.create("import_uigf");
    void this.run(job, async () => {
      const records = importUIGF(payload); this.append(job, `已校验 ${records.length} 条 UIGF 记录`, 0.5);
      job.target_uids = [...new Set(records.map(({ uid }) => uid))].sort();
      this.wishes.save(records);
      return { result: { imported: records.length, uid_count: job.target_uids.length }, message: `成功导入 ${records.length} 条记录` };
    });
    return job;
  }

  startGachaUrl(gachaUrl: string): WishTask {
    const job = this.create("import_gacha_url");
    void this.run(job, async () => {
      this.append(job, "正在校验抽卡 URL 并读取祈愿记录", null);
      const result = await this.wishes.importFromGachaUrl(gachaUrl, (value) => this.append(job, value));
      job.target_uids = result.uids;
      return { result: { inserted: result.inserted, uid_count: result.uids.length }, message: `成功导入 ${result.inserted} 条新记录` };
    });
    return job;
  }

  get(id: string): WishTask {
    const value = this.jobs.get(id);
    if (!value) throw new AppError("wish_task_missing", "祈愿任务不存在", 404);
    return value;
  }

  async wait(id: string, after: number, waitMs: number, signal?: AbortSignal): Promise<WishTask> {
    return this.notifier.wait(id, after, waitMs, () => this.get(id), signal);
  }

  private create(kind: string): WishTask {
    for (const id of pruneTerminal(this.jobs, ({ status }) => ["completed", "failed"].includes(status), (job) => this.updatedAt.get(job.id) ?? 0)) this.updatedAt.delete(id);
    if ([...this.jobs.values()].some(({ status }) => status === "queued" || status === "running")) throw new AppError("wish_task_busy", "已有祈愿任务正在运行", 409);
    const job: WishTask = { id: randomUUID(), kind, status: "queued", progress: 0, logs: [], result: null, error: "", revision: 0 };
    this.jobs.set(job.id, job); this.append(job, "后端已创建任务"); return job;
  }

  private async run(job: WishTask, operation: () => Promise<{ result: Record<string, number>; message: string }>): Promise<void> {
    try { job.status = "running"; this.touch(job); const value = await operation(); job.result = value.result; job.status = "completed"; this.append(job, value.message, 1, true); }
    catch (error) {
      job.status = "failed"; job.error = error instanceof AppError ? error.message : "祈愿任务执行失败，请稍后重试";
      job.error_code = error instanceof AppError ? error.code : "unknown_error";
      this.append(job, job.error, undefined, true);
    }
  }

  private append(job: WishTask, message: string, progress?: number | null, emphasized = false): void {
    if (progress !== undefined) job.progress = progress;
    job.logs.push({ sequence: (job.logs.at(-1)?.sequence ?? 0) + 1, message, emphasized });
    if (job.logs.length > 200) job.logs.splice(0, job.logs.length - 200);
    this.touch(job);
  }

  private touch(job: WishTask): void { this.updatedAt.set(job.id, Date.now()); this.notifier.mark(job.id, job); }
}
