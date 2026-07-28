import * as git from "isomorphic-git";
import http from "isomorphic-git/http/node";
import { expect, test, vi } from "vitest";
import { discoverMirrors, remoteOID, shallowClone } from "../src/services/metadata-remote";

vi.mock("isomorphic-git", () => ({
  clone: vi.fn(),
  listServerRefs: vi.fn(),
  resolveRef: vi.fn(),
}));
vi.mock("isomorphic-git/http/node", () => ({
  default: { request: vi.fn() },
}));

const request = vi.mocked(http.request);
const listServerRefs = vi.mocked(git.listServerRefs);
const clone = vi.mocked(git.clone);
const resolveRef = vi.mocked(git.resolveRef);

test("镜像发现拒绝异常响应", async () => {
  await expect(discoverMirrors("https://api.example", async () =>
    new Response("", { status: 503 }))).rejects.toMatchObject({ code: "metadata_discovery_failed" });
  await expect(discoverMirrors("https://api.example/", async () =>
    new Response("{"))).rejects.toMatchObject({ code: "metadata_discovery_invalid" });
  await expect(discoverMirrors("https://api.example", async () =>
    Response.json({ code: 1, data: [] }))).rejects.toMatchObject({ code: "metadata_discovery_failed" });
  await expect(discoverMirrors("https://api.example", async () =>
    Response.json({ code: 0, data: [{ https_url: "not a url" }] }))).resolves.toEqual([]);
});

test("远端 OID 通过受限 HTTPS 请求读取 main", async () => {
  request.mockResolvedValue({
    url: "https://mirror.example/info/refs",
    method: "GET",
    headers: {},
    body: chunks(new Uint8Array([1, 2, 3])),
    statusCode: 200,
    statusMessage: "OK",
  });
  listServerRefs.mockImplementation(async (options) => {
    const result = await options.http.request({
      url: "https://mirror.example/info/refs",
      method: "GET",
      headers: {},
    });
    for await (const chunk of result.body ?? []) void chunk;
    return [{ ref: "refs/heads/main", oid: "a".repeat(40) }];
  });
  await expect(remoteOID("https://mirror.example/repo.git")).resolves.toBe("a".repeat(40));
  expect(request).toHaveBeenCalledOnce();
});

test("远端 OID 拒绝不安全请求、重定向、超限响应和无效引用", async () => {
  listServerRefs.mockImplementation(async (options) => {
    await options.http.request({ url: "http://mirror.example/repo", method: "GET", headers: {} });
    return [];
  });
  await expect(remoteOID("https://mirror.example/repo.git"))
    .rejects.toMatchObject({ code: "metadata_mirror_insecure" });

  listServerRefs.mockImplementation(async (options) => {
    const result = await options.http.request({
      url: "https://mirror.example/repo", method: "GET", headers: {},
    });
    for await (const chunk of result.body ?? []) void chunk;
    return [];
  });
  request.mockResolvedValueOnce({
    url: "http://redirect.example/repo", method: "GET", headers: {}, body: undefined,
    statusCode: 302, statusMessage: "Found",
  });
  await expect(remoteOID("https://mirror.example/repo.git"))
    .rejects.toMatchObject({ code: "metadata_redirect_insecure" });

  request.mockResolvedValueOnce({
    url: "https://mirror.example/repo", method: "GET", headers: {},
    body: chunks(new Uint8Array(4 * 1024 * 1024 + 1)), statusCode: 200, statusMessage: "OK",
  });
  await expect(remoteOID("https://mirror.example/repo.git"))
    .rejects.toMatchObject({ code: "metadata_download_too_large" });

  listServerRefs.mockResolvedValueOnce([{ ref: "refs/heads/main", oid: "bad" }]);
  await expect(remoteOID("https://mirror.example/repo.git")).rejects.toThrow("远端 main 分支无效");
});

test("浅克隆固定 main 和深度并返回 HEAD", async () => {
  clone.mockImplementation(async (options) => {
    expect(options).toMatchObject({ ref: "main", depth: 1, singleBranch: true });
    const result = await options.http.request({
      url: "https://mirror.example/repo.git", method: "POST", headers: {},
    });
    expect(result.body).toBeUndefined();
  });
  request.mockResolvedValue({
    url: "https://mirror.example/repo.git", method: "POST", headers: {}, body: undefined,
    statusCode: 200, statusMessage: "OK",
  });
  resolveRef.mockResolvedValue("b".repeat(40));
  await expect(shallowClone("https://mirror.example/repo.git", "/tmp/metadata"))
    .resolves.toBe("b".repeat(40));
});

async function* chunks(...values: Uint8Array[]): AsyncGenerator<Uint8Array> {
  for (const value of values) yield value;
}
