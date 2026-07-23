import { AppError } from "../core/errors";

export async function readBoundedBody(
  response: Response, limit: number, error: () => AppError,
): Promise<Buffer> {
  const declared = response.headers.get("content-length");
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > limit)) throw error();
  if (!response.body) return Buffer.alloc(0);
  const reader = response.body.getReader(), chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > limit) {
      await reader.cancel();
      throw error();
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks, total);
}
