export function pruneTerminal<T>(
  values: Map<string, T>, terminal: (value: T) => boolean, updatedAt: (value: T) => number,
  maxEntries = 100, ttlMs = 60 * 60 * 1000, now = Date.now(),
): string[] {
  const removed: string[] = [];
  const candidates = [...values].filter(([, value]) => terminal(value)).sort((left, right) => updatedAt(left[1]) - updatedAt(right[1]));
  for (const [id, value] of candidates) {
    if (now - updatedAt(value) < ttlMs && values.size < maxEntries) continue;
    values.delete(id); removed.push(id);
  }
  return removed;
}
