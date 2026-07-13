import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { expect, test } from "vitest";
import { activate, extract, recoverActivation, safeTarget, verify } from "../src/services/installer";

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
  const root = mkdtempSync(join(tmpdir(), "activate-")), old = join(root, "game"), staging = join(root, "game.mhg-staging-test");
  mkdirSync(old); mkdirSync(staging); writeFileSync(join(old, "old"), "x"); writeFileSync(join(staging, "new"), "y");
  activate(staging, old); expect(readFileSync(join(old, "new"), "utf8")).toBe("y");
});

test("激活提交失败恢复旧目录", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-test");
  mkdirSync(game); mkdirSync(staging); writeFileSync(join(game, "old"), "x"); writeFileSync(join(staging, "new"), "y");
  expect(() => activate(staging, game, (phase) => { if (phase === "after_promote") throw new Error("fault"); })).toThrow("fault");
  expect(readFileSync(join(game, "old"), "utf8")).toBe("x"); expect(existsSync(join(game, "new"))).toBe(false);
});

test("重启恢复备份完成前中断的提交", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-crash");
  const backup = join(root, "game.mhg-backup-crash"); mkdirSync(game); mkdirSync(staging); writeFileSync(join(game, "old"), "x");
  renameSync(game, backup);
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({ schema: 1, staging_name: "game.mhg-staging-crash", backup_name: "game.mhg-backup-crash", phase: "promoting" }));
  recoverActivation(game);
  expect(readFileSync(join(game, "old"), "utf8")).toBe("x"); expect(existsSync(staging)).toBe(false);
});

test("恢复记录拒绝逃逸的备份名称", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game");
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({ schema: 1, staging_name: "game.mhg-staging-ok", backup_name: "game.mhg-backup-../../victim", phase: "promoting" }));
  expect(() => recoverActivation(game)).toThrow("恢复记录无效");
});
