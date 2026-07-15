import { createHash, type BinaryLike } from "node:crypto";
import { createReadStream } from "node:fs";
import { closeSync, fstatSync, openSync, readSync, writeSync } from "node:fs";
import xxhash from "xxhash-wasm";

type HashAlgorithm = "md5" | "sha256";

export async function hashFile(path: string, algorithm: HashAlgorithm, signal?: AbortSignal): Promise<string> {
  const hash = createHash(algorithm);
  for await (const chunk of createReadStream(path, { signal })) hash.update(chunk as BinaryLike);
  return hash.digest("hex");
}

export function hashFileSync(path: string, algorithm: HashAlgorithm): string {
  const hash = createHash(algorithm), buffer = Buffer.allocUnsafe(1024 * 1024);
  const fd = openSync(path, "r");
  try {
    for (;;) {
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (count === 0) return hash.digest("hex");
      hash.update(buffer.subarray(0, count));
    }
  } finally { closeSync(fd); }
}

export async function xxhash64File(path: string): Promise<string> {
  const hasher = (await xxhash()).create64();
  for await (const chunk of createReadStream(path)) hasher.update(chunk as Uint8Array);
  return hasher.digest().toString(16).padStart(16, "0");
}

export function copyRangeSync(source: string, target: string, start: number, length: number): void {
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(length) || start < 0 || length <= 0) throw new RangeError("invalid patch range");
  const input = openSync(source, "r");
  try {
    if (start + length > fstatSync(input).size) throw new RangeError("patch range exceeds source");
    const output = openSync(target, "wx", 0o600);
    const buffer = Buffer.allocUnsafe(1024 * 1024); let offset = start, remaining = length;
    try {
      while (remaining > 0) {
        const size = Math.min(buffer.length, remaining), count = readSync(input, buffer, 0, size, offset);
        if (count !== size) throw new RangeError("short patch read");
        let written = 0; while (written < count) written += writeSync(output, buffer, written, count - written);
        offset += count; remaining -= count;
      }
      if (remaining !== 0) throw new RangeError("short patch range");
    } finally { closeSync(output); }
  } finally { closeSync(input); }
}

export function copyRangeToDescriptorSync(
  source: string, output: number, sourceOffset: number, targetOffset: number, length: number,
): void {
  if (!Number.isSafeInteger(sourceOffset) || !Number.isSafeInteger(targetOffset)
    || !Number.isSafeInteger(length) || sourceOffset < 0 || targetOffset < 0 || length < 0) {
    throw new RangeError("invalid asset range");
  }
  const input = openSync(source, "r"), buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    if (sourceOffset + length > fstatSync(input).size) throw new RangeError("asset range exceeds source");
    let readOffset = sourceOffset, writeOffset = targetOffset, remaining = length;
    while (remaining > 0) {
      const size = Math.min(buffer.length, remaining), count = readSync(input, buffer, 0, size, readOffset);
      if (count !== size) throw new RangeError("short asset read");
      let written = 0;
      while (written < count) written += writeSync(output, buffer, written, count - written, writeOffset + written);
      readOffset += count; writeOffset += count; remaining -= count;
    }
  } finally { closeSync(input); }
}
