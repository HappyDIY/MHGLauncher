import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach } from "vitest";
import { Container } from "../src/core/container";
import { dispatch } from "../src/api/router";

const roots: string[] = [];
export function fixture(): Container {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-test-")); roots.push(dataDir);
  const value = new Container({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "test-token", providerMode: "fixture",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, socketPath: join(dataDir, "test.sock") });
  globalThis.mhgContainer = value; return value;
}
export async function request(method: string, path: string, body?: unknown, token = "test-token"): Promise<Response> {
  return dispatch(new Request(`http://local${path}`, { method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) }));
}
afterEach(() => { globalThis.mhgContainer?.close(); globalThis.mhgContainer = undefined; for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
