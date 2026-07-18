import { createHmac } from "node:crypto";
import type { PoolClient } from "pg";
import { pool } from "./db";
import type { AdminContext } from "./admin-auth";

export async function audit(context: AdminContext, action: string, targetType: string, targetRef: string,
  metadata: Record<string, unknown> = {}, client?: PoolClient): Promise<void> {
  const database = client ?? pool();
  await database.query(`INSERT INTO admin_audit_events(request_id,actor,action,target_type,target_ref,result,metadata)
    VALUES($1,$2,$3,$4,$5,'success',$6)`, [context.requestId, context.actor, action, targetType, targetRef, metadata]);
}

export async function auditFailure(context: AdminContext, request: Request, error: unknown): Promise<void> {
  const path = new URL(request.url).pathname.replace(/^\/api\/admin\/v1\/?/, "");
  const parts = path.split("/").filter(Boolean), targetType = parts[0] ?? "admin";
  const code = error instanceof Error ? error.name : "unknown_error";
  await pool().query(`INSERT INTO admin_audit_events(request_id,actor,action,target_type,target_ref,result,metadata)
    VALUES($1,$2,$3,$4,$5,'failure',$6) ON CONFLICT(request_id) DO NOTHING`,
  [context.requestId, context.actor, `${request.method.toLowerCase()}.${path.replaceAll("/", ".")}`, targetType, parts[1] ?? "-", { code }]);
}

export function privateUid(uid: string): string {
  const key = process.env.MHG_ADMIN_AUDIT_KEY || process.env.MHG_ADMIN_SERVICE_TOKEN;
  if (!key) throw new Error("MHG_ADMIN_AUDIT_KEY is required");
  return `uid_hmac:${createHmac("sha256", key).update(uid).digest("hex")}`;
}
