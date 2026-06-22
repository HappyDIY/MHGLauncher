export class AppError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 400,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

export function errorResponse(error: unknown): Response {
  if (error instanceof AppError) {
    return Response.json(
      { code: error.code, message: error.message, details: error.details },
      { status: error.status },
    );
  }
  const message = error instanceof Error ? error.message : "未知错误";
  return Response.json({ code: "internal_error", message, details: {} }, { status: 500 });
}
