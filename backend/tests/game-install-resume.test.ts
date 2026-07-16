import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import { Store } from "../src/core/database";
import { FixtureProvider } from "../src/providers/fixture";
import { GameService } from "../src/services/games";

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

function installContext(stale: boolean, expectedContent = "complete-client"): {
  root: string; destination: string; source: string; store: Store; service: GameService;
} {
  const root = mkdtempSync(join(tmpdir(), "install-resume-")), data = join(root, "data"), fixtures = join(root, "fixtures");
  const destination = join(root, "Genshin Impact Game"), source = stale ? `${destination}.mhg-staging-old` : destination;
  const content = "complete-client", md5 = createHash("md5").update(expectedContent).digest("hex");
  roots.push(root); mkdirSync(fixtures); mkdirSync(source);
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
