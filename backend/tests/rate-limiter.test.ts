import { expect, test } from "vitest";
import { TokenBucketRateLimiter, maybeRateLimiter } from "../src/services/rate-limiter";

test("不限速返回 null", () => {
  expect(maybeRateLimiter(0)).toBe(null);
  expect(maybeRateLimiter(-1)).toBe(null);
});

test("限速器可创建且容量正确", () => {
  const limiter = maybeRateLimiter(100);
  expect(limiter).not.toBe(null);
  expect(limiter!.capacity).toBe(100 * 1024);
});

test("首次获取令牌不超过容量", () => {
  const limiter = new TokenBucketRateLimiter({ bytesPerSecond: 1024 });
  const { acquired } = limiter.tryAcquire(2048);
  expect(acquired).toBe(1024);
});

test("令牌耗尽后返回零并给出等待时间", () => {
  const limiter = new TokenBucketRateLimiter({ bytesPerSecond: 1024 });
  limiter.tryAcquire(1024);
  const { acquired, retryAfterMs } = limiter.tryAcquire(1);
  expect(acquired).toBe(0);
  expect(retryAfterMs).toBeGreaterThan(0);
  expect(retryAfterMs).toBeLessThanOrEqual(50);
});

test("归还未使用令牌", () => {
  const limiter = new TokenBucketRateLimiter({ bytesPerSecond: 1024 });
  limiter.tryAcquire(1024);
  limiter.replenishTokens(512);
  const { acquired } = limiter.tryAcquire(512);
  expect(acquired).toBe(512);
});