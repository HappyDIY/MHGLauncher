import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function createTotpSecret(): string {
  return encodeBase32(randomBytes(20));
}

export function verifyTotp(secret: string, code: string, now = Date.now()): boolean {
  if (!/^\d{6}$/.test(code)) return false;
  for (const offset of [-1, 0, 1]) {
    const expected = totp(secret, Math.floor(now / 30_000) + offset);
    if (timingSafeEqual(Buffer.from(code), Buffer.from(expected))) return true;
  }
  return false;
}

export function totp(secret: string, counter = Math.floor(Date.now() / 30_000)): string {
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", decodeBase32(secret)).update(buffer).digest();
  const offset = digest[digest.length - 1]! & 15;
  const value = (digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return value.toString().padStart(6, "0");
}

function encodeBase32(value: Buffer): string {
  let bits = 0, acc = 0, output = "";
  for (const byte of value) {
    acc = (acc << 8) | byte; bits += 8;
    while (bits >= 5) { bits -= 5; output += alphabet[(acc >>> bits) & 31]; }
  }
  if (bits) output += alphabet[(acc << (5 - bits)) & 31];
  return output;
}

function decodeBase32(value: string): Buffer {
  let bits = 0, acc = 0; const output: number[] = [];
  for (const char of value.replace(/=+$/, "").toUpperCase()) {
    const index = alphabet.indexOf(char); if (index < 0) throw new Error("TOTP secret invalid");
    acc = (acc << 5) | index; bits += 5;
    if (bits >= 8) { bits -= 8; output.push((acc >>> bits) & 255); }
  }
  return Buffer.from(output);
}
