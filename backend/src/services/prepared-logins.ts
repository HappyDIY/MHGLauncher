import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { AccountIdentity, GameRole, PreparedLogin } from "../core/models";

interface Pending extends PreparedLogin { source: string; generation: number; expires: number }

export class PreparedLoginStore {
  private generation = 0;
  private readonly pending = new Map<string, Pending>();
  private readonly consumedSources = new Set<string>();
  private readonly reservations = new Map<string, number>();

  begin(source: string): void {
    this.generation += 1;
    this.pending.clear();
    this.consumedSources.delete(source);
    this.reservations.set(source, this.generation);
  }

  prepare(source: string, identity: AccountIdentity, roles: GameRole[]): PreparedLogin {
    this.sweep();
    if (this.reservations.get(source) !== this.generation) throw new AppError("login_intent_stale", "登录请求已被更新的操作取代", 409);
    if (this.consumedSources.has(source)) throw new AppError("login_consumed", "登录事务已使用", 409);
    const existing = [...this.pending.values()].find((value) => value.source === source);
    if (existing) return publicValue(existing);
    const expires = Date.now() + 5 * 60_000;
    const value: Pending = {
      transaction_id: randomUUID(), identity, roles, expires_at: new Date(expires).toISOString(),
      source, generation: this.generation, expires,
    };
    this.pending.set(value.transaction_id, value);
    return publicValue(value);
  }

  consume(id: string): PreparedLogin {
    this.sweep();
    const value = this.pending.get(id);
    if (!value || value.generation !== this.generation) throw new AppError("login_transaction_invalid", "登录事务无效或已过期", 409);
    this.pending.delete(id);
    this.consumedSources.add(value.source);
    return publicValue(value);
  }

  abort(id: string): void { this.pending.delete(id); }

  private sweep(): void {
    const now = Date.now();
    for (const [id, value] of this.pending) if (value.expires <= now) this.pending.delete(id);
  }
}

function publicValue(value: Pending): PreparedLogin {
  return { transaction_id: value.transaction_id, identity: value.identity, roles: value.roles, expires_at: value.expires_at };
}
