import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { stopWineServer } from "../src/services/game-wine-server";

test("Wine 服务原本未运行时停止操作保持幂等", async () => {
  const server = fakeServer('if [ "$1" = "-k" ]; then exit 1; fi\nexit 0');
  await expect(stopWineServer(server, "/tmp/prefix")).resolves.toBeUndefined();
});

test("Wine 服务停止命令真实失败时返回领域错误", async () => {
  const server = fakeServer('echo failed >&2\nexit 2');
  await expect(stopWineServer(server, "/tmp/prefix")).rejects.toMatchObject({ code: "wine_server_stop_failed" });
});

function fakeServer(body: string): string {
  const root = mkdtempSync(join(tmpdir(), "wine-server-")), path = join(root, "wineserver");
  writeFileSync(path, `#!/bin/sh\n${body}\n`); chmodSync(path, 0o700); return path;
}
