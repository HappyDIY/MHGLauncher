import { beforeAll, describe, expect, test } from "vitest";
import { decrypt, encrypt, hashPassword, verifyPassword } from "../lib/crypto";
import { createTotpSecret, totp, verifyTotp } from "../lib/totp";

beforeAll(() => { process.env.MHG_ADMIN_ENCRYPTION_KEY = "11".repeat(32); });

describe("站长认证原语", () => {
  test("Argon2id 密码摘要可校验且使用随机盐", async () => {
    const first = await hashPassword("correct horse battery staple");
    const second = await hashPassword("correct horse battery staple");
    expect(first).not.toBe(second);
    expect(await verifyPassword("correct horse battery staple", first)).toBe(true);
    expect(await verifyPassword("wrong password", first)).toBe(false);
  });

  test("TOTP 接受相邻时间窗并拒绝无效格式", () => {
    const secret = createTotpSecret(), now = 1_800_000_000_000;
    expect(verifyTotp(secret, totp(secret, Math.floor(now / 30_000)), now)).toBe(true);
    expect(verifyTotp(secret, "123", now)).toBe(false);
  });

  test("TOTP 密钥使用认证加密往返", () => {
    const secret = createTotpSecret(), encoded = encrypt(secret);
    expect(encoded).not.toContain(secret);
    expect(decrypt(encoded)).toBe(secret);
  });
});
