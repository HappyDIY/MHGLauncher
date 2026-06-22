import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { WishTask } from "../core/models";
import type { AccountService } from "./accounts";
import { importUIGF } from "./uigf";
import type { WishService } from "./wishes";

export class WishTasks {
  private readonly jobs = new Map<string, WishTask>();
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
      this.wishes.save(records);
      return { result: { imported: records.length }, message: `成功导入 ${records.length} 条记录` };
    });
    return job;
  }

  get(id: string): WishTask {
    const value = this.jobs.get(id);
    if (!value) throw new AppError("wish_task_missing", "祈愿任务不存在", 404);
    return value;
  }

  private create(kind: string): WishTask {
    if ([...this.jobs.values()].some(({ status }) => status === "queued" || status === "running")) throw new AppError("wish_task_busy", "已有祈愿任务正在运行", 409);
    const job: WishTask = { id: randomUUID(), kind, status: "queued", progress: 0, logs: [], result: null, error: "" };
    this.jobs.set(job.id, job); this.append(job, "后端已创建任务"); return job;
  }

  private async run(job: WishTask, operation: () => Promise<{ result: Record<string, number>; message: string }>): Promise<void> {
    try { job.status = "running"; const value = await operation(); job.result = value.result; job.status = "completed"; this.append(job, value.message, 1, true); }
    catch (error) { job.status = "failed"; job.error = error instanceof Error ? error.message : "祈愿任务执行失败"; this.append(job, job.error, undefined, true); }
  }

  private append(job: WishTask, message: string, progress?: number | null, emphasized = false): void {
    if (progress !== undefined) job.progress = progress;
    job.logs.push({ sequence: job.logs.length + 1, message, emphasized });
  }
}
