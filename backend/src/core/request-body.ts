import { AppError } from "./errors";

export async function readJsonBody(request: Request, maxBytes = 1024 * 1024): Promise<unknown> {
  const declared = request.headers.get("content-length");
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) throw tooLarge(maxBytes);
  if (!request.body) throw invalidJson();
  const reader = request.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    total += value.length;
    if (total > maxBytes) { await reader.cancel(); throw tooLarge(maxBytes); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks, total).toString("utf8")) as unknown; }
  catch { throw invalidJson(); }
}

function tooLarge(maxBytes: number): AppError {
  return new AppError("request_too_large", `请求体不能超过 ${maxBytes} 字节`, 413);
}
function invalidJson(): AppError { return new AppError("invalid_json", "请求体必须是有效 JSON", 400); }
