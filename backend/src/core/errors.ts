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
  if (error instanceof AppError || isSerializedAppError(error)) {
    return Response.json(
      { code: error.code, message: error.message, details: error.details },
      { status: error.status },
    );
  }
  const message = error instanceof Error ? error.message : "未知错误";
  return Response.json({ code: "internal_error", message, details: {} }, { status: 500 });
}

function isSerializedAppError(error: unknown): error is AppError {
  if (!(error instanceof Error)) return false;
  const value = error as Partial<AppError>;
  return typeof value.code === "string" && typeof value.status === "number"
    && value.status >= 400 && value.status < 600 && typeof value.details === "object";
}
