import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, statSync, symlinkSync, writeFileSync } from "node:fs";
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

test("解压前拒绝符号链接条目", () => {
  const root = mkdtempSync(join(tmpdir(), "install-link-")), source = join(root, "source"), archive = join(root, "game.zip");
  mkdirSync(source); symlinkSync("/tmp", join(source, "escape"));
  expect(spawnSync("/usr/bin/zip", ["-y", "-q", archive, "escape"], { cwd: source }).status).toBe(0);
  expect(() => extract([archive], join(root, "staging"))).toThrow("链接或特殊文件");
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

test("新安装提升后的清理中断不会删除唯一客户端", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-test");
  mkdirSync(staging); writeFileSync(join(staging, "new"), "y");
  expect(() => activate(staging, game, (phase) => { if (phase === "before_cleanup") throw new Error("fault"); })).toThrow("fault");
  expect(readFileSync(join(game, "new"), "utf8")).toBe("y"); expect(existsSync(staging)).toBe(false);
  recoverActivation(game); expect(readFileSync(join(game, "new"), "utf8")).toBe("y");
});

test("新安装提交竞态不会删除后来出现的用户目录", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-race-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-test");
  mkdirSync(staging); writeFileSync(join(staging, "new"), "game");
  expect(() => activate(staging, game, (phase) => {
    if (phase === "after_backup") { mkdirSync(game); writeFileSync(join(game, "user.txt"), "keep"); }
  }, false)).toThrow();
  expect(readFileSync(join(game, "user.txt"), "utf8")).toBe("keep");
  expect(readFileSync(join(staging, "new"), "utf8")).toBe("game");
});

test("新安装在提升前崩溃时恢复完整暂存目录", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-crash");
  mkdirSync(staging); writeFileSync(join(staging, "new"), "y");
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({ schema: 2, staging_name: "game.mhg-staging-crash", backup_name: "game.mhg-backup-crash", phase: "backing_up", staging: identity(staging), destination: null }));
  recoverActivation(game);
  expect(readFileSync(join(game, "new"), "utf8")).toBe("y"); expect(existsSync(staging)).toBe(false);
});

test("重启恢复备份完成前中断的提交", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game"), staging = join(root, "game.mhg-staging-crash");
  const backup = join(root, "game.mhg-backup-crash"); mkdirSync(game); mkdirSync(staging); writeFileSync(join(game, "old"), "x");
  const destination = identity(game), staged = identity(staging);
  renameSync(game, backup);
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({ schema: 2, staging_name: "game.mhg-staging-crash", backup_name: "game.mhg-backup-crash", phase: "promoting", staging: staged, destination }));
  recoverActivation(game);
  expect(readFileSync(join(game, "old"), "utf8")).toBe("x"); expect(existsSync(staging)).toBe(false);
});

test("恢复记录拒绝逃逸的备份名称", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-")), game = join(root, "game");
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({ schema: 1, staging_name: "game.mhg-staging-ok", backup_name: "game.mhg-backup-../../victim", phase: "promoting" }));
  expect(() => recoverActivation(game)).toThrow("恢复记录无效");
});

test("恢复记录目录身份不符时不删除任何目录", () => {
  const root = mkdtempSync(join(tmpdir(), "activate-conflict-")), game = join(root, "game");
  const staging = join(root, "game.mhg-staging-safe"), backup = join(root, "game.mhg-backup-safe");
  mkdirSync(game); mkdirSync(staging); mkdirSync(backup); writeFileSync(join(game, "user.txt"), "keep");
  writeFileSync(`${game}.mhg-activation.json`, JSON.stringify({
    schema: 2, staging_name: "game.mhg-staging-safe", backup_name: "game.mhg-backup-safe", phase: "promoting",
    staging: { dev: "0", ino: "0" }, destination: identity(backup),
  }));
  expect(() => recoverActivation(game)).toThrow("拒绝自动删除");
  expect(readFileSync(join(game, "user.txt"), "utf8")).toBe("keep");
  expect(existsSync(staging)).toBe(true); expect(existsSync(backup)).toBe(true);
});

function identity(path: string): { dev: string; ino: string } {
  const stat = statSync(path, { bigint: true }); return { dev: stat.dev.toString(), ino: stat.ino.toString() };
}
