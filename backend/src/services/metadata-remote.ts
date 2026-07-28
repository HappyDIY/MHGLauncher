import * as git from "isomorphic-git";
import http from "isomorphic-git/http/node";
import fs from "node:fs";
import { z } from "zod";
import { AppError } from "../core/errors";
import { readBoundedBody } from "./http-response";

const mirror = z.object({ https_url: z.string() }).passthrough();
const responseSchema = z.object({ data: z.array(mirror).max(32), code: z.number(), message: z.string().optional() }).passthrough();

export async function discoverMirrors(apiBaseUrl: string, fetcher: typeof fetch = fetch): Promise<string[]> {
  const url = new URL("/git-repository/all?name=Snap.Metadata", withSlash(apiBaseUrl));
  const response = await fetcher(url, { signal: AbortSignal.timeout(30_000) });
  if (!response.ok) throw new AppError("metadata_discovery_failed", `资料镜像发现失败：${response.status}`, 502);
  const bytes = await readBoundedBody(response, 1024 * 1024, () =>
    new AppError("metadata_discovery_invalid", "资料镜像响应过大", 502));
  let parsed: z.infer<typeof responseSchema>;
  try { parsed = responseSchema.parse(JSON.parse(Buffer.from(bytes).toString("utf8"))); }
  catch { throw new AppError("metadata_discovery_invalid", "资料镜像响应无效", 502); }
  if (parsed.code !== 0) throw new AppError("metadata_discovery_failed", "资料镜像服务返回失败", 502);
  return parsed.data.flatMap(({ https_url }) => secureURL(https_url) ? [https_url] : []);
}

export async function remoteOID(url: string): Promise<string> {
  const refs = await git.listServerRefs({ http: limitedHttp(4 * 1024 * 1024), url, prefix: "refs/heads/main" });
  const oid = refs.find((value) => value.ref === "refs/heads/main")?.oid;
  if (!oid || !/^[a-f0-9]{40,64}$/.test(oid)) throw new Error("远端 main 分支无效");
  return oid;
}

export async function shallowClone(url: string, dir: string): Promise<string> {
  await git.clone({
    fs, http: limitedHttp(128 * 1024 * 1024), dir, url, ref: "main", depth: 1, singleBranch: true,
  });
  return await git.resolveRef({ fs, dir, ref: "HEAD" });
}

function limitedHttp(limit: number) {
  let received = 0;
  return {
    request: async (args: Parameters<typeof http.request>[0]) => {
      if (!secureURL(args.url)) throw new AppError("metadata_mirror_insecure", "资料镜像必须使用无凭据的 HTTPS 地址", 502);
      const result = await http.request(args);
      if (result.url && !secureURL(result.url)) throw new AppError("metadata_redirect_insecure", "资料镜像重定向不安全", 502);
      const body = result.body;
      if (!body) return result;
      return { ...result, body: (async function* () {
        for await (const chunk of body) {
          received += chunk.byteLength;
          if (received > limit) throw new AppError("metadata_download_too_large", "资料下载量超过限制", 502);
          yield chunk;
        }
      })() };
    },
  };
}

function secureURL(value: string): boolean {
  try { const url = new URL(value); return url.protocol === "https:" && !url.username && !url.password; }
  catch { return false; }
}
function withSlash(value: string): string { return value.endsWith("/") ? value : `${value}/`; }
