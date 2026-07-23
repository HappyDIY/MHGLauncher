import { createServer } from "node:net";
import { mkdtempSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import {
  releaseSocket, requireUnusedSocketPath, socketIdentity, withPrivateSocketUmask,
} from "../src/core/server-socket";

describe("Unix Socket 所有权", () => {
  test("拒绝删除普通文件", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "mhg-socket-")), "server.sock");
    writeFileSync(path, "user-data");
    await expect(requireUnusedSocketPath(path)).rejects.toThrow("已存在");
  });

  test("只释放自己监听的 socket inode", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "mhg-socket-")), "server.sock");
    const server = createServer();
    await new Promise<void>((resolve, reject) => server.once("error", reject).listen(path, resolve));
    const identity = await socketIdentity(path);
    await expect(releaseSocket(path, { ...identity, ino: identity.ino + 1 })).resolves.toBeUndefined();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await expect(releaseSocket(path, identity)).resolves.toBeUndefined();
  });

  test("监听建立时 socket 从一开始就是 0600", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "mhg-socket-")), "server.sock");
    const server = createServer();
    await withPrivateSocketUmask(() => new Promise<void>((resolve, reject) => {
      server.once("error", reject).listen(path, resolve);
    }));
    expect(statSync(path).mode & 0o777).toBe(0o600);
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });
});
