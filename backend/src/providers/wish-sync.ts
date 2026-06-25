import { AppError } from "../core/errors";

export type WishSyncSleeper = () => Promise<void>;

export const wishSyncLimitedMessage = "访问过于频繁，请稍后再同步祈愿记录";

export async function defaultWishSyncSleeper(): Promise<void> {
  const milliseconds = 1_000 + Math.floor(Math.random() * 1_000);
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function normalizeWishSyncError(error: unknown): never {
  if (isVisitTooFrequently(error)) {
    throw new AppError("wish_sync_limited", wishSyncLimitedMessage, 429);
  }
  throw error;
}

export function isVisitTooFrequently(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return error.message.toLowerCase().includes("visit too frequently");
}
