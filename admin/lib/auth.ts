import "server-only";
import { headers } from "next/headers";
import { decrypt, digest, verifyPassword } from "./crypto";
import { pool, ready } from "./db";
import { verifyTotp } from "./totp";

export async function authenticate(email: string, password: string, code: string): Promise<boolean> {
  await ready();
  const source = digest((await headers()).get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown");
  const emailHash = digest(email.toLowerCase());
  const attempts = await pool().query(`SELECT COUNT(*) FILTER(WHERE created_at>now()-interval '15 minutes') failures,
    MAX(created_at) last_failure FROM admin.login_attempts WHERE email_hash=$1 AND source_hash=$2
    AND succeeded=false AND created_at>now()-interval '30 minutes'`, [emailHash, source]);
  if (Number(attempts.rows[0].failures) >= 5 && Date.now() - attempts.rows[0].last_failure.getTime() < 30 * 60 * 1000) return false;
  const result = await pool().query("SELECT email,password_hash,totp_secret FROM admin.owner WHERE lower(email)=lower($1)", [email]);
  const owner = result.rows[0];
  let accepted = false;
  if (owner && await verifyPassword(password, owner.password_hash)) {
    accepted = verifyTotp(decrypt(owner.totp_secret), code) || await consumeRecoveryCode(code);
  }
  await pool().query("INSERT INTO admin.login_attempts(email_hash,source_hash,succeeded) VALUES($1,$2,$3)", [emailHash, source, accepted]);
  await pool().query("INSERT INTO admin.auth_audit_events(action,result,source_hash) VALUES('login',$1,$2)", [accepted ? "success" : "failure", source]);
  return accepted;
}

export async function verifyOwnerTotp(code: string): Promise<boolean> {
  const result = await pool().query("SELECT totp_secret FROM admin.owner WHERE id=1");
  return Boolean(result.rows[0] && verifyTotp(decrypt(result.rows[0].totp_secret), code));
}

async function consumeRecoveryCode(code: string): Promise<boolean> {
  const result = await pool().query(`UPDATE admin.recovery_codes SET used_at=now()
    WHERE code_hash=$1 AND owner_id=1 AND used_at IS NULL RETURNING code_hash`, [digest(code.toUpperCase())]);
  return Boolean(result.rowCount);
}
