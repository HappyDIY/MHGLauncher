export interface Revisioned { revision?: number }

type Resolver = () => void;

export class RevisionNotifier<T extends Revisioned> {
  private readonly waiters = new Map<string, Set<Resolver>>();

  mark(id: string, value: T): T {
    value.revision = (value.revision ?? 0) + 1;
    this.release(id);
    return value;
  }

  async wait(id: string, after: number, ms: number, read: () => T): Promise<T> {
    const current = read();
    if ((current.revision ?? 0) > after || ms <= 0) return current;
    await new Promise<void>((resolve) => {
      const set = this.waiters.get(id) ?? new Set<Resolver>();
      set.add(resolve); this.waiters.set(id, set);
      setTimeout(() => { set.delete(resolve); resolve(); }, ms).unref();
    });
    return read();
  }

  private release(id: string): void {
    const set = this.waiters.get(id);
    if (!set) return;
    this.waiters.delete(id);
    for (const resolve of set) resolve();
  }
}

export interface LongPollOptions { after: number; waitMs: number }

export function longPollOptions(query: URLSearchParams): LongPollOptions {
  const after = Math.max(0, Number(query.get("after_revision") ?? 0) || 0);
  const requested = Math.max(0, Number(query.get("wait_ms") ?? 0) || 0);
  return { after, waitMs: Math.min(requested, 2_000) };
}
