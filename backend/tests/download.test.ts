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
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

test("续传部分下载", async () => {
  const dir = root(), target = join(dir, "game.zip"), content = Buffer.from("0123456789"); writeFileSync(`${target}.part`, content.subarray(0, 4));
  let range = ""; vi.stubGlobal("fetch", vi.fn(async (_url, init) => { range = new Headers(init?.headers).get("Range") ?? ""; return new Response(content.subarray(4), { status: 206, headers: { "Content-Range": "bytes 4-9/10" } }); }));
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
    return new Response(content.subarray(4), { status: 206, headers: { "Content-Range": "bytes 4-9/10" } });
  }));
  await download({ url: "https://fixture/retry", md5: createHash("md5").update(content).digest("hex"), size: content.length, filename: "retry" }, target, new DownloadControl(), () => undefined);
  expect(resumedRange).toBe("bytes=4-"); expect(readFileSync(target)).toEqual(content);
});

test("取消控制会中断检查点", async () => { const control = new DownloadControl(); control.cancel(); await expect(control.checkpoint()).rejects.toThrow("任务已取消"); });
test("暂停后可恢复", async () => { const control = new DownloadControl(); control.pause(); const waiting = control.checkpoint(); control.resume(); await expect(waiting).resolves.toBeUndefined(); });

test("只有 worker 到达暂停屏障后才确认暂停", async () => {
  const control = new DownloadControl(), acknowledged = control.pause(); let paused = false;
  void acknowledged.then(() => { paused = true; }); await Promise.resolve(); expect(paused).toBe(false);
  const checkpoint = control.checkpoint(); await acknowledged; expect(paused).toBe(true); control.resume(); await checkpoint;
});

test("拒绝错位续传响应并从零重新下载", async () => {
  const target = join(root(), "range"), content = Buffer.from("0123456789"); writeFileSync(`${target}.part`, content.subarray(0, 4)); let calls = 0;
  vi.stubGlobal("fetch", vi.fn(async () => ++calls === 1
    ? new Response("evil", { status: 206, headers: { "Content-Range": "bytes 0-3/10" } })
    : new Response(content)));
  await download({ url: "https://fixture/range", md5: createHash("md5").update(content).digest("hex"), size: content.length, filename: "range" }, target, new DownloadControl(), () => undefined);
  expect(calls).toBe(2); expect(readFileSync(target)).toEqual(content);
});

test("读取停滞会在期限内失败而非永久挂起", async () => {
  vi.stubEnv("MHG_DOWNLOAD_STALL_TIMEOUT_MS", "50");
  vi.stubGlobal("fetch", vi.fn(async () => new Response(new ReadableStream({ start() {} }))));
  const pending = download({ url: "https://fixture/stall", md5: "", size: 1, filename: "stall" }, join(root(), "stall"), new DownloadControl(), () => undefined);
  await expect(pending).rejects.toThrow("长时间无数据");
});

test("持续传输超过停滞期限不会断开重连", async () => {
  vi.stubEnv("MHG_DOWNLOAD_STALL_TIMEOUT_MS", "50");
  const target = join(root(), "slow"), content = Buffer.from("12345"); let calls = 0;
  vi.stubGlobal("fetch", vi.fn(async (_url, init: RequestInit) => {
    calls += 1;
    const offset = Number(/bytes=(\d+)-/.exec(new Headers(init.headers).get("Range") ?? "")?.[1] ?? 0);
    const body = content.subarray(offset);
    const scheduled: { value: ReturnType<typeof setTimeout> | undefined } = { value: undefined };
    return new Response(new ReadableStream({
      start(controller) {
        let index = 0;
        const send = () => {
          if (index === body.length) { controller.close(); return; }
          controller.enqueue(body.subarray(index, index + 1)); index += 1;
          scheduled.value = setTimeout(send, 20);
        };
        init.signal?.addEventListener("abort", () => { if (scheduled.value) clearTimeout(scheduled.value); controller.error(init.signal?.reason); });
        send();
      },
      cancel() { if (scheduled.value) clearTimeout(scheduled.value); },
    }));
  }));
  await download({ url: "https://fixture/slow", md5: createHash("md5").update(content).digest("hex"), size: content.length, filename: "slow" }, target, new DownloadControl(), () => undefined);
  expect(calls).toBe(1); expect(readFileSync(target)).toEqual(content);
});

test("取消会中断挂起的下载请求", async () => {
  const control = new DownloadControl(); let signal: AbortSignal | undefined;
  vi.stubGlobal("fetch", vi.fn((_url, init: RequestInit) => new Promise<Response>((_resolve, reject) => {
    signal = init.signal ?? undefined;
    signal?.addEventListener("abort", () => reject(signal?.reason));
  })));
  const pending = download({ url: "https://fixture/hang", md5: "", size: 1, filename: "hang" }, join(root(), "hang"), control, () => undefined);
  await vi.waitFor(() => expect(signal).toBeDefined());
  control.cancel();
  await expect(pending).rejects.toMatchObject({ name: "AbortError" });
});

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

test("范围复制拒绝越界和非安全整数且不产生输出", () => {
  const dir = root(), source = join(dir, "patch.bin"); writeFileSync(source, "1234");
  expect(() => copyRangeSync(source, join(dir, "overflow"), 3, 2)).toThrow("exceeds source");
  expect(() => copyRangeSync(source, join(dir, "unsafe"), Number.MAX_SAFE_INTEGER + 1, 1)).toThrow("invalid patch range");
  expect(existsSync(join(dir, "overflow"))).toBe(false);
});
