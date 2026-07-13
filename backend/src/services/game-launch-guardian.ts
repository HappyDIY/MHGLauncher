import { closeSync, fsyncSync, mkdirSync, openSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { recoverInterruptedDlls } from "./game-launch-recovery";

export class DllRecoveryGuardian {
  private timer: NodeJS.Timeout | null = null;
  private isPending = false;
  private warningList: string[] = [];

  constructor(private readonly dataDir: string, private readonly recovered: () => void = () => undefined) { this.refresh(); }

  refresh(): void {
    const wasPending = this.isPending;
    const result = recoverInterruptedDlls(this.dataDir);
    this.isPending = result.pending;
    if (result.warnings.length) {
      this.warningList = [...new Set([...this.warningList, ...result.warnings])]; this.persist();
    }
    if (this.isPending && !this.timer) this.timer = setInterval(() => this.refresh(), 1_000);
    if (!this.isPending && this.timer) { clearInterval(this.timer); this.timer = null; }
    if (wasPending && !this.isPending) this.recovered();
  }

  pending(): boolean { return this.isPending; }
  warnings(): string[] { return [...this.warningList]; }

  async drain(active: () => boolean): Promise<void> {
    while (active() || this.isPending) {
      this.refresh(); await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }

  close(): void { if (this.timer) clearInterval(this.timer); this.timer = null; }

  private persist(): void {
    const directory = join(this.dataDir, "launches"); mkdirSync(directory, { recursive: true, mode: 0o700 });
    const target = join(directory, "recovery-warnings.json"), temp = `${target}.${process.pid}.tmp`;
    writeFileSync(temp, JSON.stringify({ warnings: this.warningList, updated_at: new Date().toISOString() }), { mode: 0o600 });
    const descriptor = openSync(temp, "r"); try { fsyncSync(descriptor); } finally { closeSync(descriptor); }
    renameSync(temp, target);
    const parent = openSync(directory, "r"); try { fsyncSync(parent); } finally { closeSync(parent); }
  }
}
