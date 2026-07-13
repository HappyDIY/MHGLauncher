import { existsSync, realpathSync } from "node:fs";
import { resolve } from "node:path";
import { AppError } from "../core/errors";

export interface ResourceLease { key: string; owner: string }

export class ResourceCoordinator {
  private readonly owners = new Map<string, string>();

  claim(path: string, owner: string): ResourceLease {
    const key = existsSync(path) ? realpathSync(path) : resolve(path);
    const current = this.owners.get(key);
    if (current && current !== owner) throw new AppError("game_resource_busy", "游戏目录正在被其他任务使用", 409);
    this.owners.set(key, owner);
    return { key, owner };
  }

  release(lease: ResourceLease): void {
    if (this.owners.get(lease.key) === lease.owner) this.owners.delete(lease.key);
  }

  busy(path: string): boolean {
    const key = existsSync(path) ? realpathSync(path) : resolve(path);
    return this.owners.has(key);
  }
}
