import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import {
  containedPath, ensureOwnedDirectory, removeOwnedDirectory, safeBasename, safeIdentifier,
} from "../src/core/safe-path";

describe("受管路径", () => {
  test("拒绝目录穿越和复合文件名", () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-path-"));
    expect(() => containedPath(root, "../outside")).toThrow("路径不安全");
    expect(() => safeBasename("dir/file", "文件")).toThrow("单一文件名");
    expect(() => safeIdentifier("../../tag", "版本")).toThrow("不安全字符");
  });

  test("拒绝父目录符号链接", () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-path-"));
    const outside = mkdtempSync(join(tmpdir(), "mhg-outside-"));
    symlinkSync(outside, join(root, "linked"));
    expect(() => containedPath(root, "linked/file.bin")).toThrow("链接");
  });

  test("只删除匹配所有权标记的目录", () => {
    const root = join(mkdtempSync(join(tmpdir(), "mhg-owned-")), "stage");
    ensureOwnedDirectory(root, "job-1");
    writeFileSync(join(root, "payload"), "ok");
    expect(() => removeOwnedDirectory(root, "job-2")).toThrow("不属于启动器");
    expect(() => removeOwnedDirectory(root, "job-1")).not.toThrow();
  });

  test("拒绝把普通目录冒充为受管目录", () => {
    const root = join(mkdtempSync(join(tmpdir(), "mhg-owned-")), "stage");
    mkdirSync(root);
    expect(() => ensureOwnedDirectory(root, "job-1")).toThrow("不属于启动器");
  });
});
