import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import { Store } from "../src/core/database";
import { FixtureProvider } from "../src/providers/fixture";
import { GameService } from "../src/services/games";
import { cleanupStaleUpdateStaging, createGameStaging } from "../src/services/game-staging";
import { gameOperationPaths } from "../src/services/game-install-resume";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("正式目录中的未完成安装会预检复用并补齐客户端标记", async () => {
  const context = installContext(false);
  try {
    const executableInode = statSync(join(context.destination, "YuanShen.exe")).ino;
    const state = await context.service.state(context.destination);
    expect(state).toMatchObject({ install_path: context.destination, installed_version: "6.7.0", status: "damaged", download_bytes: 0 });
    expect((await context.service.spaceCheck(context.destination, 0, "install")).required).toBe(1024 ** 3);
    expect((await wait(context.service, await context.service.start("install", context.destination))).status).toBe("completed");
    expect(readFileSync(join(context.destination, "config.ini"), "utf8")).toContain("game_version=6.7.0");
    expect(readFileSync(join(context.destination, ".mhg-version"), "utf8")).toBe("6.7.0");
    expect(existsSync(join(context.destination, ".mhg-staging-version"))).toBe(false);
    expect(statSync(join(context.destination, "YuanShen.exe")).ino).toBe(executableInode);
    expect((await context.service.state(context.destination)).status).toBe("ready");
  } finally { context.store.close(); }
});

test("崩溃残留的 staging 目录会被续接并提升为正式目录", async () => {
  const context = installContext(true);
  try {
    const executableInode = statSync(join(context.source, "YuanShen.exe")).ino;
    expect((await context.service.state(context.destination)).download_bytes).toBe(0);
    expect((await wait(context.service, await context.service.start("install", context.destination))).status).toBe("completed");
    expect(existsSync(context.destination)).toBe(true); expect(existsSync(context.source)).toBe(false);
    expect(readFileSync(join(context.destination, "YuanShen.exe"), "utf8")).toBe("complete-client");
    expect(statSync(join(context.destination, "YuanShen.exe")).ino).toBe(executableInode);
  } finally { context.store.close(); }
});

test.each([{ stale: false, label: "正式目录" }, { stale: true, label: "崩溃暂存目录" }])("$label 原地续接失败时保留客户端与续接标记", async ({ stale }) => {
  const context = installContext(stale, "replacement-client");
  try {
    const job = await wait(context.service, await context.service.start("install", context.destination));
    expect(job.status).toBe("failed");
    expect(readFileSync(join(context.source, "YuanShen.exe"), "utf8")).toBe("complete-client");
    expect(readFileSync(join(context.source, ".mhg-staging-version"), "utf8")).toBe("6.7.0");
  } finally { context.store.close(); }
});

test("原地续接遇到本地写入错误时返回明确原因", async () => {
  const context = installContext(false, "replacement-client");
  try {
    chmodSync(context.source, 0o500);
    const job = await wait(context.service, await context.service.start("install", context.destination));
    expect(job).toMatchObject({ status: "failed", message: "本地存储写入失败：EACCES" });
  } finally { chmodSync(context.source, 0o700); context.store.close(); }
});

test("全新安装失败时保留尚未生成可执行文件的续接目录", async () => {
  const root = mkdtempSync(join(tmpdir(), "install-failure-")), data = join(root, "data"), fixtures = join(root, "fixtures"), destination = join(root, "Genshin Impact Game");
  roots.push(root); mkdirSync(fixtures);
  writeFileSync(join(fixtures, "build.json"), JSON.stringify({
    version: "6.7.0", assets: [{ name: "YuanShen.exe", size: 1, md5: createHash("md5").update("x").digest("hex"), chunks: [] }],
  }));
  const store = new Store(join(data, "test.db")), service = new GameService(store, new FixtureProvider(fixtures), data);
  try {
    expect((await wait(service, await service.start("install", destination))).status).toBe("failed");
    const staging = join(root, readdirSync(root).find((name) => name.startsWith("Genshin Impact Game.mhg-staging-")) ?? "missing");
    expect(existsSync(join(staging, ".mhg-staging-version"))).toBe(true);
    expect(existsSync(join(staging, "YuanShen.exe"))).toBe(false);
    expect(await service.state(destination)).toMatchObject({ status: "damaged", installed_version: "6.7.0" });
  } finally { store.close(); }
});

test("全新安装不会把已有用户目录当作可替换的游戏目录", async () => {
  const root = mkdtempSync(join(tmpdir(), "install-target-")), selected = join(root, "Documents");
  const fixtures = join(root, "fixtures"), data = join(root, "data");
  roots.push(root); mkdirSync(selected); mkdirSync(fixtures); writeFileSync(join(selected, "user.txt"), "keep");
  writeFileSync(join(fixtures, "build.json"), JSON.stringify({ version: "6.7.0" }));
  expect(gameOperationPaths("install", selected).root).toBe(join(realpathSync(selected), "Genshin Impact Game"));
  const store = new Store(join(data, "test.db")), service = new GameService(store, new FixtureProvider(fixtures), data);
  try {
    await expect(service.start("install", selected)).rejects.toMatchObject({ code: "game_build_empty" });
    expect(readFileSync(join(selected, "user.txt"), "utf8")).toBe("keep");
  } finally { store.close(); }
});

test("同名非空安装目录和无所有权旧标记都不会被覆盖", async () => {
  const root = mkdtempSync(join(tmpdir(), "install-unowned-")), destination = join(root, "Genshin Impact Game");
  const fixtures = join(root, "fixtures"), data = join(root, "data"); roots.push(root);
  mkdirSync(destination); mkdirSync(fixtures); writeFileSync(join(destination, "user.txt"), "keep");
  writeFileSync(join(destination, ".mhg-staging-version"), "6.7.0");
  writeFileSync(join(fixtures, "build.json"), JSON.stringify({ version: "6.7.0" }));
  const store = new Store(join(data, "test.db")), service = new GameService(store, new FixtureProvider(fixtures), data);
  try {
    await expect(service.start("install", destination)).rejects.toMatchObject({ code: "install_destination_not_empty" });
    expect(readFileSync(join(destination, "user.txt"), "utf8")).toBe("keep");
  } finally { store.close(); }
});

test("只清理已失去进程所有权的更新暂存副本", () => {
  const root = mkdtempSync(join(tmpdir(), "stale-update-")), destination = join(root, "game");
  const staging = `${destination}.mhg-staging-old`; roots.push(root);
  const record = createGameStaging(staging, "old-update", "update", destination, "6.7.0");
  writeFileSync(join(staging, "payload"), "copy"); cleanupStaleUpdateStaging(destination);
  expect(existsSync(staging)).toBe(true);
  writeFileSync(join(staging, ".mhg-staging.json"), JSON.stringify({ ...record, pid: 2_147_483_647 }));
  cleanupStaleUpdateStaging(destination); expect(existsSync(staging)).toBe(false);
});

function installContext(stale: boolean, expectedContent = "complete-client"): {
  root: string; destination: string; source: string; store: Store; service: GameService;
} {
  const root = mkdtempSync(join(tmpdir(), "install-resume-")), data = join(root, "data"), fixtures = join(root, "fixtures");
  const destination = join(root, "Genshin Impact Game"), source = stale ? `${destination}.mhg-staging-old` : destination;
  const content = "complete-client", md5 = createHash("md5").update(expectedContent).digest("hex");
  roots.push(root); mkdirSync(fixtures); createGameStaging(source, "resume-test", "install", destination, "6.7.0");
  writeFileSync(join(source, "YuanShen.exe"), content); writeFileSync(join(source, ".mhg-staging-version"), "6.7.0");
  writeFileSync(join(source, "pkg_version"), JSON.stringify({ remoteName: "YuanShen.exe", md5 }));
  writeFileSync(join(fixtures, "build.json"), JSON.stringify({
    version: "6.7.0", assets: [{ name: "YuanShen.exe", size: expectedContent.length, md5, chunks: [] }],
  }));
  const store = new Store(join(data, "test.db"));
  return { root, destination, source, store, service: new GameService(store, new FixtureProvider(fixtures), data) };
}

async function wait(service: GameService, initial: ReturnType<GameService["get"]>): Promise<ReturnType<GameService["get"]>> {
  let job = initial; for (let index = 0; index < 100 && !["completed", "failed", "cancelled"].includes(job.status); index += 1) {
    await new Promise((resolve) => setTimeout(resolve, 10)); job = service.get(job.id);
  }
  return job;
}
