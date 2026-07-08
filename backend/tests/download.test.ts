import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import xxhash from "xxhash-wasm";
import { afterEach, expect, test, vi } from "vitest";
import { DownloadControl, download } from "../src/services/download";
import { copyRangeSync, hashFile, hashFileSync, xxhash64File } from "../src/services/file-hash";

const roots: string[] = [];
const root = (): string => { const value = mkdtempSync(join(tmpdir(), "download-")); roots.push(value); return value; };
afterEach(() => { vi.unstubAllGlobals(); });

test("续传部分下载", async () => {
  const dir = root(), target = join(dir, "game.zip"), content = Buffer.from("0123456789"); writeFileSync(`${target}.part`, content.subarray(0, 4));
  let range = ""; vi.stubGlobal("fetch", vi.fn(async (_url, init) => { range = new Headers(init?.headers).get("Range") ?? ""; return new Response(content.subarray(4), { status: 206 }); }));
  await download({ url: "https://fixture/game", md5: createHash("md5").update(content).digest("hex"), size: content.length, filename: "game.zip" }, target, new DownloadControl(), () => undefined);
  expect(range).toBe("bytes=4-"); expect(readFileSync(target)).toEqual(content);
});

test("删除哈希错误的临时文件", async () => {
  const dir = root(), target = join(dir, "bad.zip"); vi.stubGlobal("fetch", vi.fn(async () => new Response("bad")));
  await expect(download({ url: "https://fixture/bad", md5: "0".repeat(32), size: 3, filename: "bad.zip" }, target, new DownloadControl(), () => undefined)).rejects.toThrow("校验失败");
  expect(existsSync(`${target}.part`)).toBe(false);
});

test("拒绝大小不一致", async () => {
  const target = join(root(), "small"); vi.stubGlobal("fetch", vi.fn(async () => new Response("x")));
  await expect(download({ url: "https://fixture/small", md5: "", size: 2, filename: "small" }, target, new DownloadControl(), () => undefined)).rejects.toThrow("自动重试 5 次");
  expect(statSync(`${target}.part`).size).toBe(1);
});

test("连接中断后从已落盘位置自动续传", async () => {
  const target = join(root(), "retry"), content = Buffer.from("0123456789"); let calls = 0, resumedRange = "";
  vi.stubGlobal("fetch", vi.fn(async (_url, init) => {
    calls += 1;
    if (calls === 1) return new Response(content.subarray(0, 4));
    resumedRange = new Headers(init?.headers).get("Range") ?? "";
    return new Response(content.subarray(4), { status: 206 });
  }));
  await download({ url: "https://fixture/retry", md5: createHash("md5").update(content).digest("hex"), size: content.length, filename: "retry" }, target, new DownloadControl(), () => undefined);
  expect(resumedRange).toBe("bytes=4-"); expect(readFileSync(target)).toEqual(content);
});

test("取消控制会中断检查点", async () => { const control = new DownloadControl(); control.cancel(); await expect(control.checkpoint()).rejects.toThrow("任务已取消"); });
test("暂停后可恢复", async () => { const control = new DownloadControl(); control.pause(); const waiting = control.checkpoint(); control.resume(); await expect(waiting).resolves.toBeUndefined(); });

test("文件哈希使用流式结果", async () => {
  const path = join(root(), "hash.bin"), content = Buffer.from("streamed-hash-content");
  writeFileSync(path, content);
  expect(await hashFile(path, "md5")).toBe(createHash("md5").update(content).digest("hex"));
  expect(hashFileSync(path, "sha256")).toBe(createHash("sha256").update(content).digest("hex"));
});

test("xxhash 与范围复制不读取整块补丁", async () => {
  const dir = root(), source = join(dir, "patch.bin"), target = join(dir, "segment.bin");
  const content = Buffer.from("0123456789abcdef"); writeFileSync(source, content);
  copyRangeSync(source, target, 4, 6);
  expect(readFileSync(target).toString()).toBe("456789");
  expect(await xxhash64File(source)).toBe((await xxhash()).h64Raw(content).toString(16).padStart(16, "0"));
});
