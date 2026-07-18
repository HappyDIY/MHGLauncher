import "server-only";
import { randomUUID } from "node:crypto";

export class CloudAdminError extends Error {
  constructor(public readonly status: number, message: string) { super(message); }
}

export async function cloudRequest<T>(path: string, actor: string, init?: RequestInit): Promise<T> {
  const base = process.env.MHG_CLOUD_INTERNAL_URL, token = process.env.MHG_ADMIN_SERVICE_TOKEN;
  if (!base || !token) throw new CloudAdminError(503, "管理服务尚未配置");
  const response = await fetch(`${base.replace(/\/$/, "")}/api/admin/v1${path}`, {
    ...init, cache: "no-store", signal: AbortSignal.timeout(10_000),
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json",
      "X-MHG-Admin-Actor": actor, "X-Request-ID": randomUUID().replaceAll("-", ""), ...init?.headers },
  }).catch(() => { throw new CloudAdminError(503, "云端管理服务暂时不可用"); });
  if (!response.ok) {
    const body = await response.json().catch(() => ({})) as { message?: string };
    throw new CloudAdminError(response.status, body.message ?? "云端管理请求失败");
  }
  return response.json() as Promise<T>;
}
