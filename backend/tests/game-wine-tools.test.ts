import { EventEmitter } from "node:events";
import {
  mkdirSync, mkdtempSync, rmSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { GameWineToolService, wineToolArguments } from "../src/services/game-wine-tools";

const roots: string[] = [];
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("生成 Wine 内置工具参数", () => {
  expect(wineToolArguments({ action: "preferences", performance_profile: "baseline" })).toEqual(["winecfg.exe"]);
  expect(wineToolArguments({ action: "run", command: " regedit ", performance_profile: "compatibility" }))
    .toEqual(["regedit"]);
  expect(wineToolArguments({ action: "run", command: "\"C:\\Program Files\\app.exe\" --flag", performance_profile: "baseline" }))
    .toEqual(["C:\\Program Files\\app.exe", "--flag"]);
  expect(() => wineToolArguments({ action: "run", command: " ", performance_profile: "optimized" }))
    .toThrow("请输入要运行的 Windows 命令");
});

test("使用既有 Wine 容器启动工具且不经过 shell", async () => {
  const fixture = readyFixture(), child = new FakeChild();
  const spawn = vi.fn(() => {
    queueMicrotask(() => child.emit("spawn")); return child;
  });
  const service = new GameWineToolService(fixture.dataDir, fixture.runtimeRoot, () => false, spawn as never);
  await service.start({ action: "run", command: "cmd /c dir", performance_profile: "optimized" });
  expect(spawn).toHaveBeenCalledWith(fixture.wine, ["cmd", "/c", "dir"], expect.objectContaining({
    detached: true, stdio: "ignore", env: expect.objectContaining({
      WINEPREFIX: fixture.prefix, WINEDLLOVERRIDES: "winedbg.exe=d",
    }),
  }));
  expect(child.unref).toHaveBeenCalledOnce();
});

test("文件管理器改用 Finder 打开 Wine 系统盘", async () => {
  const fixture = readyFixture(), child = new FakeChild();
  const spawn = vi.fn(() => {
    queueMicrotask(() => child.emit("spawn")); return child;
  });
  const service = new GameWineToolService(fixture.dataDir, fixture.runtimeRoot, () => false, spawn as never);
  await service.start({ action: "explorer", performance_profile: "optimized" });
  expect(spawn).toHaveBeenCalledWith("/usr/bin/open", [join(fixture.prefix, "drive_c")], expect.objectContaining({
    detached: true, stdio: "ignore",
  }));
});

test("游戏运行时拒绝启动 Wine 工具", async () => {
  const fixture = readyFixture();
  const service = new GameWineToolService(fixture.dataDir, fixture.runtimeRoot, () => true);
  await expect(service.start({ action: "explorer", performance_profile: "optimized" }))
    .rejects.toMatchObject({ code: "wine_tool_busy" });
});

class FakeChild extends EventEmitter {
  unref = vi.fn();
}

function readyFixture(): { runtimeRoot: string; dataDir: string; prefix: string; wine: string } {
  const root = mkdtempSync(join(tmpdir(), "mhg-wine-tool-")); roots.push(root);
  const runtimeRoot = join(root, "runtime"), dataDir = join(root, "data");
  const prefix = join(dataDir, "wineprefix"), wine = join(runtimeRoot, "wine/bin/wine");
  for (const path of [
    wine, join(runtimeRoot, "wine/bin/wineboot"), join(runtimeRoot, "wine/bin/wineserver"),
    join(runtimeRoot, "wine/lib/wine/x86_64-windows/winemetal.dll"),
    join(runtimeRoot, "bin/mhg-window-probe"), join(runtimeRoot, "lib/libmhg_dns_gate.dylib"),
    join(runtimeRoot, "assets/mhypbase.dll"),
  ]) {
    mkdirSync(join(path, ".."), { recursive: true }); writeFileSync(path, "fixture");
  }
  mkdirSync(prefix, { recursive: true });
  writeFileSync(join(prefix, ".mhglauncher-wine-runtime"), `${wine}\n`);
  return { runtimeRoot, dataDir, prefix, wine };
}
