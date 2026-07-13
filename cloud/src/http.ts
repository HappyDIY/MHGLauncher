export class HttpError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string) {
    super(message);
  }
}

export function json(value: unknown, status = 200): Response {
  return Response.json(value, { status });
}

export function fail(error: unknown): Response {
  if (error instanceof HttpError) return json({ code: error.code, message: error.message }, error.status);
  return json({ code: "internal_error", message: "云端服务异常" }, 500);
}

export function bearer(request: Request): string {
  const token = request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  if (!token) throw new HttpError(401, "unauthorized", "缺少云端令牌");
  return token;
}
