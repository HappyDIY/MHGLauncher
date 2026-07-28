import { lstatSync, readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";

const MAX_FILES = 10_000;
const MAX_FILE_BYTES = 8 * 1024 * 1024;
const MAX_TOTAL_BYTES = 384 * 1024 * 1024;
const required = ["GachaEvent", "Weapon", "Reliquary", "Achievement", "AchievementGoal"];
const metadataKey = /^(?:GachaEvent|Weapon|Reliquary|Achievement|AchievementGoal|Avatar\/[1-9]\d{0,15})$/;

export async function validateMetadataRepository(root: string): Promise<void> {
  const chs = join(root, "Genshin", "CHS");
  const paths = walk(root).filter((path) => !relative(root, path).startsWith(".git/"));
  if (paths.length > MAX_FILES) invalid("资料文件数量超过限制");
  let total = 0;
  for (const path of paths) {
    const info = lstatSync(path);
    if (info.isSymbolicLink() || !info.isFile()) invalid("资料仓库包含不安全的文件");
    if (info.size > MAX_FILE_BYTES) invalid("资料文件大小超过限制");
    total += info.size;
  }
  if (total > MAX_TOTAL_BYTES) invalid("资料仓库总大小超过限制");
  const meta = parseJSON(join(chs, "Meta.json")) as Record<string, unknown>;
  if (!meta || typeof meta !== "object" || Array.isArray(meta)) invalid("资料摘要文件无效");
  if (Object.keys(meta).some((key) => key.includes("..") || key.startsWith("/") || key.includes("\\"))) {
    invalid("资料摘要包含非法路径");
  }
  const keys = [...required, ...Object.keys(meta).filter((key) => key.startsWith("Avatar/"))];
  if (keys.length <= required.length || keys.some((key) => !metadataKey.test(key))) invalid("资料摘要包含非法路径");
  const { h64Raw } = await xxhash();
  for (const key of keys) {
    const expected = meta[key];
    if (typeof expected !== "string" || !/^[A-F0-9]{16}$/.test(expected)) invalid("资料摘要格式无效");
    const path = join(chs, `${key}.json`);
    const data = readFileSync(path);
    const canonical = Buffer.from(data.toString("utf8").replace(/\r?\n/g, "\r\n"));
    const hashes = [data, canonical].map((value) =>
      h64Raw(value).toString(16).padStart(16, "0").toUpperCase());
    if (!hashes.includes(expected)) invalid(`资料文件校验失败：${key}`);
    checkDepth(parseJSON(path), 0);
  }
}

function walk(root: string): string[] {
  const output: string[] = [];
  const visit = (directory: string) => {
    for (const name of readdirSync(directory)) {
      const path = join(directory, name), rel = relative(root, path);
      if (rel === ".git" || rel.startsWith(`.git/`)) continue;
      const info = lstatSync(path);
      if (info.isDirectory()) visit(path); else output.push(path);
      if (output.length > MAX_FILES) return;
    }
  };
  visit(root); return output;
}

function parseJSON(path: string): unknown {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch { invalid("资料 JSON 文件无效"); }
}

function checkDepth(value: unknown, depth: number): void {
  if (depth > 64) invalid("资料 JSON 嵌套层级超过限制");
  if (Array.isArray(value)) for (const item of value) checkDepth(item, depth + 1);
  else if (value && typeof value === "object") for (const item of Object.values(value)) checkDepth(item, depth + 1);
}

function invalid(message: string): never {
  throw new AppError("metadata_invalid", message, 502);
}
