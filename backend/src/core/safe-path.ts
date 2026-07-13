import {
  closeSync, constants, existsSync, lstatSync, mkdirSync, openSync, readFileSync, rmSync, writeFileSync,
} from "node:fs";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { AppError } from "./errors";

const identifier = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/;
const markerName = ".mhg-owner.json";

export function safeIdentifier(value: string, label: string): string {
  if (!identifier.test(value) || value === "." || value === "..") {
    throw new AppError("path_identifier_invalid", `${label} 包含不安全字符`, 422);
  }
  return value;
}

export function safeBasename(value: string, label: string): string {
  if (value !== basename(value) || value.includes("\\") || value.includes("\0")) {
    throw new AppError("path_identifier_invalid", `${label} 必须是单一文件名`, 422);
  }
  return safeIdentifier(value, label);
}

export function containedPath(root: string, name: string, allowExistingLeaf = true): string {
  const normalized = name.replaceAll("\\", "/");
  if (!normalized || normalized.includes("\0") || isAbsolute(normalized) || normalized.split("/").includes("..")) {
    throw new AppError("archive_path_unsafe", `路径不安全：${name}`, 422);
  }
  const canonicalRoot = resolve(root), target = resolve(canonicalRoot, normalized);
  const child = relative(canonicalRoot, target);
  if (!child || child.startsWith(`..${sep}`) || child === ".." || isAbsolute(child)) {
    throw new AppError("archive_path_unsafe", `路径不安全：${name}`, 422);
  }
  assertNoSymlink(canonicalRoot, child, allowExistingLeaf);
  return target;
}

export function ensureOwnedDirectory(path: string, owner: string): void {
  const marker = resolve(path, markerName), identity = safeIdentifier(owner, "目录所有者");
  if (existsSync(path)) {
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new AppError("managed_path_invalid", "受管路径不是普通目录", 409);
    if (!existsSync(marker) || JSON.parse(readFileSync(marker, "utf8") as string).owner !== identity) {
      throw new AppError("managed_path_unowned", "拒绝使用不属于启动器的目录", 409);
    }
    return;
  }
  mkdirSync(path, { recursive: true, mode: 0o700 });
  writeExclusive(marker, JSON.stringify({ owner: identity, created_at: new Date().toISOString() }));
}

export function removeOwnedDirectory(path: string, owner: string): void {
  if (!existsSync(path)) return;
  ensureOwnedDirectory(path, owner);
  rmSync(path, { recursive: true });
}

function writeExclusive(path: string, content: string | Uint8Array, mode = 0o600): void {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const fd = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, mode);
  try { writeFileSync(fd, content); } finally { closeSync(fd); }
}

function assertNoSymlink(root: string, child: string, allowExistingLeaf: boolean): void {
  if (existsSync(root)) {
    const rootStat = lstatSync(root);
    if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new AppError("archive_path_unsafe", "根目录不安全", 422);
  }
  const parts = child.split(sep), limit = allowExistingLeaf ? parts.length : Math.max(parts.length - 1, 0);
  let cursor = root;
  for (let index = 0; index < limit; index += 1) {
    const part = parts[index];
    if (!part) continue;
    cursor = resolve(cursor, part);
    if (!existsSync(cursor)) break;
    const stat = lstatSync(cursor);
    if (stat.isSymbolicLink() || (index < parts.length - 1 && !stat.isDirectory())) {
      throw new AppError("archive_path_unsafe", `路径包含链接或非目录父级：${child}`, 422);
    }
  }
}
