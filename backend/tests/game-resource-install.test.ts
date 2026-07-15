import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import { normalizeBuild } from "../src/providers/provider";
import { DownloadControl } from "../src/services/download";
import { installGameResources } from "../src/services/game-resource-install";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("下载完成后的完整性校验可暂停并继续", async () => {
  const root = mkdtempSync(join(tmpdir(), "resource-install-")), staging = join(root, "game"), cache = join(root, "cache");
  const content = Buffer.alloc(1024 * 1024, 3), control = new DownloadControl();
  const reached = Promise.withResolvers<void>(), acknowledged = Promise.withResolvers<void>();
  roots.push(root); mkdirSync(staging); writeFileSync(join(staging, "YuanShen.exe"), content);
  const build = normalizeBuild({ version: "6.6.0", assets: [{
    name: "YuanShen.exe", size: content.length,
    md5: createHash("md5").update(content).digest("hex"), chunks: [],
  }] });
  const operation = installGameResources({
    build, kind: "install", staging, cache, control, workers: 1, limiter: null,
    progress: () => undefined, chunk: () => undefined, reserve: () => undefined,
    phase: (phase) => {
      if (phase === "verify") { reached.resolve(); void control.pause().then(acknowledged.resolve); }
    },
  });
  await reached.promise; await acknowledged.promise;
  let settled = false; void operation.finally(() => { settled = true; });
  await new Promise((resolve) => setTimeout(resolve, 10)); expect(settled).toBe(false);
  control.resume(); await expect(operation).resolves.toMatchObject({ version: "6.6.0" });
});
