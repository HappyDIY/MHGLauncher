import { lstat, unlink } from "node:fs/promises";
import { AppError } from "./errors";
import { acquirePrivateUmask } from "./private-umask";

export interface SocketIdentity { dev: number; ino: number }

export async function withPrivateSocketUmask<T>(action: () => Promise<T>): Promise<T> {
  const restoreUmask = acquirePrivateUmask(0o177);
  try { return await action(); }
  finally { restoreUmask(); }
}

export async function requireUnusedSocketPath(path: string): Promise<void> {
  try {
    await lstat(path);
    throw new AppError("socket_path_in_use", "Unix Socket 路径已存在", 409);
  } catch (error) {
    if (error instanceof AppError) throw error;
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

export async function socketIdentity(path: string): Promise<SocketIdentity> {
  const stat = await lstat(path);
  if (!stat.isSocket()) throw new AppError("socket_path_invalid", "监听路径不是 Unix Socket", 500);
  return { dev: stat.dev, ino: stat.ino };
}

export async function releaseSocket(path: string, expected: SocketIdentity): Promise<void> {
  try {
    const stat = await lstat(path);
    if (!stat.isSocket() || stat.dev !== expected.dev || stat.ino !== expected.ino) return;
    await unlink(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}
