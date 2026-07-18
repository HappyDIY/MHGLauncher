import { randomBytes } from "node:crypto";
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { digest, encrypt, hashPassword } from "../lib/crypto";
import { pool, ready } from "../lib/db";
import { createTotpSecret, verifyTotp } from "../lib/totp";

const prompt = createInterface({ input: stdin, output: stdout });
try {
  await ready();
  const exists = Boolean((await pool().query("SELECT 1 FROM admin.owner WHERE id=1")).rowCount);
  if (exists && !process.argv.includes("--reset")) throw new Error("站长账号已存在；确认重置时请添加 --reset");
  const email = (await prompt.question("站长邮箱：")).trim().toLowerCase();
  const password = await prompt.question("站长密码（至少 12 位）：");
  if (!/^\S+@\S+\.\S+$/.test(email) || password.length < 12) throw new Error("邮箱或密码不符合要求");
  const secret = createTotpSecret();
  const uri = `otpauth://totp/MHGLauncher:${encodeURIComponent(email)}?secret=${secret}&issuer=MHGLauncher&digits=6&period=30`;
  console.log(`请将以下 URI 添加到验证器：\n${uri}`);
  const code = (await prompt.question("输入当前 6 位验证码：")).trim();
  if (!verifyTotp(secret, code)) throw new Error("TOTP 验证失败，未创建账号");
  const recovery = Array.from({ length: 10 }, () => randomBytes(6).toString("hex").toUpperCase());
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    if (exists) await client.query("DELETE FROM admin.owner WHERE id=1");
    await client.query("INSERT INTO admin.owner(id,email,password_hash,totp_secret) VALUES(1,$1,$2,$3)",
      [email, await hashPassword(password), encrypt(secret)]);
    for (const value of recovery) await client.query("INSERT INTO admin.recovery_codes(code_hash,owner_id) VALUES($1,1)", [digest(value)]);
    await client.query("COMMIT");
  } catch (error) { await client.query("ROLLBACK"); throw error; } finally { client.release(); }
  console.log(`站长账号创建完成。恢复码仅显示一次：\n${recovery.join("\n")}`);
} finally {
  prompt.close();
  await pool().end();
}
