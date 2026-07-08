import { createHash, type BinaryLike } from "node:crypto";
import { createReadStream } from "node:fs";
import { closeSync, openSync, readSync, writeSync } from "node:fs";
import xxhash from "xxhash-wasm";

type HashAlgorithm = "md5" | "sha256";

export async function hashFile(path: string, algorithm: HashAlgorithm): Promise<string> {
  const hash = createHash(algorithm);
  for await (const chunk of createReadStream(path)) hash.update(chunk as BinaryLike);
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
  const input = openSync(source, "r"), output = openSync(target, "w");
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  let offset = start, remaining = length;
  try {
    while (remaining > 0) {
      const size = Math.min(buffer.length, remaining);
      const count = readSync(input, buffer, 0, size, offset);
      if (count <= 0) break;
      writeSync(output, buffer, 0, count);
      offset += count; remaining -= count;
    }
  } finally { closeSync(input); closeSync(output); }
}
