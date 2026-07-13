import type { DownloadControl } from "./download";

export async function concurrentMap<T, R>(
  items: T[], limit: number, control: DownloadControl, task: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length); let next = 0, failure: unknown;
  async function worker(): Promise<void> {
    while (next < items.length && failure === undefined) {
      const index = next++, item = items[index]; if (item === undefined) continue;
      try { results[index] = await task(item); }
      catch (error) { failure ??= error; control.abortWorkers(failure); }
    }
  }
  await Promise.allSettled(Array.from({ length: Math.min(Math.max(limit, 1), items.length) }, worker));
  if (failure !== undefined) throw failure;
  return results;
}
