export interface RateLimitOptions { bytesPerSecond: number }

export interface AcquireResult { acquired: number; retryAfterMs: number }

const REPLENISH_HZ = 20;
const REPLENISH_INTERVAL_MS = 1000 / REPLENISH_HZ;

export class TokenBucketRateLimiter {
  private tokens: number;
  private lastReplenish: number;
  readonly capacity: number;

  constructor(options: RateLimitOptions) {
    this.capacity = options.bytesPerSecond;
    this.tokens = Math.min(this.capacity, options.bytesPerSecond);
    this.lastReplenish = now();
  }

  private replenish(): void {
    const t = now();
    const elapsed = t - this.lastReplenish;
    const periods = Math.floor(elapsed / REPLENISH_INTERVAL_MS);
    if (periods <= 0) return;
    this.lastReplenish += periods * REPLENISH_INTERVAL_MS;
    const add = (this.capacity / REPLENISH_HZ) * periods;
    this.tokens = Math.min(this.capacity, this.tokens + add);
  }

  tryAcquire(permits: number): AcquireResult {
    this.replenish();
    const acquired = Math.min(permits, Math.floor(this.tokens));
    this.tokens -= acquired;
    if (acquired > 0) return { acquired, retryAfterMs: 0 };
    return { acquired: 0, retryAfterMs: REPLENISH_INTERVAL_MS - ((now() - this.lastReplenish) % REPLENISH_INTERVAL_MS) };
  }

  replenishTokens(count: number): void {
    if (count <= 0) return;
    this.tokens = Math.min(this.capacity, this.tokens + count);
  }
}

export type RateLimiter = TokenBucketRateLimiter | null;

export function maybeRateLimiter(speedLimitKB: number): RateLimiter {
  if (speedLimitKB <= 0) return null;
  return new TokenBucketRateLimiter({ bytesPerSecond: speedLimitKB * 1024 });
}

function now(): number { return performance.now(); }