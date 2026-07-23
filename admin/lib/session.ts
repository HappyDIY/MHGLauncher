import "server-only";
import { randomBytes } from "node:crypto";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { digest } from "./crypto";
import { pool, ready } from "./db";

const cookieName = "mhg_admin_session";

export type AdminSession = { email: string; csrf: string; tokenHash: string };

export async function requireSession(): Promise<AdminSession> {
  const token = (await cookies()).get(cookieName)?.value ?? "";
  if (!token) redirect("/login");
  await ready();
  const tokenHash = digest(token);
  const result = await pool().query(`UPDATE admin.admin_sessions s SET last_seen_at=now() FROM admin.owner o
    WHERE s.token_hash=$1 AND s.owner_id=o.id AND s.revoked_at IS NULL
    AND s.expires_at>now() AND s.last_seen_at>now()-interval '12 hours'
    RETURNING o.email,s.csrf_token`, [tokenHash]);
  if (!result.rows[0]) redirect("/login");
  return { email: String(result.rows[0].email), csrf: String(result.rows[0].csrf_token), tokenHash };
}

export async function createSession(): Promise<void> {
  const token = randomBytes(32).toString("base64url"), csrf = randomBytes(24).toString("base64url");
  await ready();
  await pool().query(`INSERT INTO admin.admin_sessions(token_hash,owner_id,csrf_token,expires_at)
    VALUES($1,1,$2,now()+interval '7 days')`, [digest(token), csrf]);
  (await cookies()).set(cookieName, token, { httpOnly: true, secure: process.env.NODE_ENV === "production",
    sameSite: "strict", path: "/", maxAge: 7 * 24 * 60 * 60 });
}

export async function revokeCurrentSession(): Promise<void> {
  const token = (await cookies()).get(cookieName)?.value;
  if (token) await pool().query("UPDATE admin.admin_sessions SET revoked_at=now() WHERE token_hash=$1", [digest(token)]);
  (await cookies()).delete(cookieName);
}

export async function verifyMutation(csrf: FormDataEntryValue | null): Promise<AdminSession> {
  const session = await requireSession();
  const requestHeaders = await headers(), origin = requestHeaders.get("origin"), expected = process.env.MHG_ADMIN_ORIGIN;
  if (!expected || origin !== new URL(expected).origin || csrf !== session.csrf) throw new Error("请求安全校验失败");
  return session;
}
