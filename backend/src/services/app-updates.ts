import { z } from "zod";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import { readBoundedBody } from "./http-response";

const manifest = z.object({
  version: z.string().regex(/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/),
  download_url: z.string().url().max(2_048),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  size: z.number().int().positive().max(4 * 1024 * 1024 * 1024),
  changelog: z.string().min(1).max(20_000),
}).strict().superRefine((value, context) => {
  const url = new URL(value.download_url);
  if (url.protocol !== "https:" || url.username || url.password) {
    context.addIssue({ code: "custom", path: ["download_url"], message: "更新地址无效" });
  }
});

export type AppUpdateManifest = z.infer<typeof manifest>;
type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export class AppUpdateService {
  constructor(private readonly settings: Settings, private readonly fetcher: Fetcher = fetch) {}

  async latest(): Promise<AppUpdateManifest> {
    const baseUrl = this.settings.cloudBaseUrl?.trim() ?? "";
    if (!baseUrl) throw new AppError("cloud_not_configured", "云端服务尚未配置", 503);
    let response: Response;
    try {
      response = await this.fetcher(`${baseUrl}/api/v1/updates/latest`, {
        method: "GET", headers: { Accept: "application/json" }, signal: AbortSignal.timeout(15_000),
      });
    } catch {
      throw new AppError("update_check_failed", "暂时无法检查应用更新", 503);
    }
    const invalid = () => new AppError("update_payload_invalid", "云端更新信息无效", 502);
    const text = (await readBoundedBody(response, 1024 * 1024, invalid)).toString("utf8");
    let payload: unknown;
    try { payload = JSON.parse(text); }
    catch { throw new AppError("update_payload_invalid", "云端更新信息无效", 502); }
    if (!response.ok) {
      const value = z.object({ message: z.string().max(1_024).optional() }).passthrough().safeParse(payload);
      throw new AppError("update_check_failed", value.success ? value.data.message ?? "暂时无法检查应用更新" : "暂时无法检查应用更新", response.status);
    }
    const parsed = manifest.safeParse(payload);
    if (!parsed.success) throw new AppError("update_payload_invalid", "云端更新信息无效", 502);
    return parsed.data;
  }
}
