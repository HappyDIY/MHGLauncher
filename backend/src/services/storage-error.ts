import { AppError } from "../core/errors";

const localWriteErrors = new Set(["EACCES", "EDQUOT", "ENOSPC", "EROFS"]);

export function localStorageError(error: unknown): unknown {
  const code = (error as NodeJS.ErrnoException).code;
  return code && localWriteErrors.has(code)
    ? new AppError("storage_write_failed", `本地存储写入失败：${code}`, 507)
    : error;
}
