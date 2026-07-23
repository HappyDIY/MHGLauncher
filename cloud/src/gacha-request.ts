import { resolve4 } from "node:dns/promises";
import { request as httpsRequest } from "node:https";
import { HttpError } from "./http";

export type GachaRequester = (url: URL) => Promise<Response>;

export const requestGacha: GachaRequester = async (url) => {
  let addresses: string[];
  try { addresses = await resolve4(url.hostname); }
  catch { addresses = []; }
  const unique = [...new Set(addresses)];
  const offset = unique.length ? Date.now() % unique.length : 0;
  const ordered = [...unique.slice(offset), ...unique.slice(0, offset)].slice(0, 5);
  for (const address of ordered) {
    try { return await requestAddress(url, address); }
    catch { continue; }
  }
  throw new HttpError(503, "gacha_upstream_unavailable", "抽卡服务暂时不可用，请稍后重试");
};

function requestAddress(url: URL, address: string): Promise<Response> {
  return new Promise((resolve, reject) => {
    const request = httpsRequest(url, {
      lookup: (_hostname, _options, callback) => callback(null, address, 4),
    }, (response) => {
      const chunks: Buffer[] = [];
      let size = 0;
      response.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > 1024 * 1024) request.destroy(new Error("response_too_large"));
        else chunks.push(chunk);
      });
      response.on("end", () => resolve(new Response(Buffer.concat(chunks), { status: response.statusCode ?? 502 })));
      response.on("error", reject);
    });
    request.setTimeout(5_000, () => request.destroy(new Error("timeout")));
    request.on("error", reject);
    request.end();
  });
}
