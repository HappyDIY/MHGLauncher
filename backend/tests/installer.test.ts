import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { expect, test } from "vitest";
import { activate, extract, safeTarget, verify } from "../src/services/installer";

test("拒绝路径穿越", () => expect(() => safeTarget("/tmp/root", "../escape")).toThrow("路径不安全"));
test("拒绝绝对路径", () => expect(() => safeTarget("/tmp/root", "/escape")).toThrow("路径不安全"));
test("允许根目录内文件", () => expect(safeTarget("/tmp/root", "a/b")).toBe("/tmp/root/a/b"));

test("解压并验证 ZIP", () => {
  const root = mkdtempSync(join(tmpdir(), "install-")), source = join(root, "source"), archive = join(root, "game.zip"), staging = join(root, "staging");
  mkdirSync(source); writeFileSync(join(source, "file.txt"), "ok"); writeFileSync(join(source, "mhg-manifest.json"), JSON.stringify({ files: {} }));
  expect(spawnSync("/usr/bin/zip", ["-qr", archive, "."], { cwd: source }).status).toBe(0);
  extract([archive], staging); verify(staging); expect(readFileSync(join(staging, "file.txt"), "utf8")).toBe("ok");
});

test("激活替换旧目录", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), old = join(root, "game"), staging = join(root, "staging");
  mkdirSync(old); mkdirSync(staging); writeFileSync(join(old, "old"), "x"); writeFileSync(join(staging, "new"), "y");
  activate(staging, old); expect(readFileSync(join(old, "new"), "utf8")).toBe("y");
});
