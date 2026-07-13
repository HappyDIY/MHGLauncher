import { HttpError } from "./http";

export async function readJsonBody(request: Request, maxBytes: number): Promise<unknown> {
  const declared = request.headers.get("content-length");
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) throw tooLarge();
  if (!request.body) throw invalidJson();
  const reader = request.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break; total += value.length;
    if (total > maxBytes) { await reader.cancel(); throw tooLarge(); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks, total).toString("utf8")) as unknown; }
  catch { throw invalidJson(); }
}

function tooLarge(): HttpError { return new HttpError(413, "request_too_large", "请求体超过大小限制"); }
function invalidJson(): HttpError { return new HttpError(400, "invalid_json", "请求体必须是有效 JSON"); }
