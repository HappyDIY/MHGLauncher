import { argon2, createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from "node:crypto";

const parameters = { parallelism: 1, tagLength: 32, memory: 65_536, passes: 3 };

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await derive(password, salt);
  return `${salt.toString("base64url")}.${hash.toString("base64url")}`;
}

export async function verifyPassword(password: string, encoded: string): Promise<boolean> {
  const [saltValue, expectedValue] = encoded.split(".");
  if (!saltValue || !expectedValue) return false;
  const expected = Buffer.from(expectedValue, "base64url");
  const actual = await derive(password, Buffer.from(saltValue, "base64url"));
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function derive(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => argon2("argon2id", { ...parameters, message: password, nonce: salt }, (error, value) => {
    if (error) reject(error); else resolve(Buffer.from(value));
  }));
}

export function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function encrypt(value: string): string {
  const key = encryptionKey(), iv = randomBytes(12), cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return [iv, cipher.getAuthTag(), encrypted].map((part) => part.toString("base64url")).join(".");
}

export function decrypt(value: string): string {
  const [iv, tag, encrypted] = value.split(".").map((part) => Buffer.from(part, "base64url"));
  if (!iv || !tag || !encrypted) throw new Error("encrypted value invalid");
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8");
}

function encryptionKey(): Buffer {
  const raw = process.env.MHG_ADMIN_ENCRYPTION_KEY ?? "";
  const key = /^[a-fA-F0-9]{64}$/.test(raw) ? Buffer.from(raw, "hex") : Buffer.from(raw, "base64url");
  if (key.length !== 32) throw new Error("MHG_ADMIN_ENCRYPTION_KEY must contain 32 bytes");
  return key;
}
