import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { createGameAccountRegistryValue, restoreGameAccountRegistry, writeGameAccountRegistry, type RegistryAccount } from "../src/services/game-account-registry";

const roots: string[] = [];
const account: RegistryAccount = { aid: "10001", mid: "mid-1", nickname: "旅行者", credential: "stoken=stoken-value; cookie_token=cookie-token; mid=mid-1" };

afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("游戏账号注册表", () => {
  test("SDK 字符串可用源项目 DES-CBC 规则解密", () => {
    const mac = "A1B2C3D4E5F6";
    const sdk = createGameAccountRegistryValue(account, mac, 1_700_000_000);
    const result = decrypt(sdk, mac.slice(0, 8));
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout).data[0]).toMatchObject({
      uid: "10001", mid: "mid-1", token: "cookie-token", accessToken: "cookie-token",
      stoken: "stoken-value", is_login: true,
      thirdLoginTimestamp: 1_700_000_000, loginTime: 1_700_000_000,
    });
  });

  test("旧凭据缺少 cookie_token 时回退到 stoken", () => {
    const sdk = createGameAccountRegistryValue({ ...account, credential: "stoken=stoken-value; mid=mid-1" }, "A1B2C3D4E5F6");
    const result = decrypt(sdk, "A1B2C3D4");
    expect(JSON.parse(result.stdout).data[0]).toMatchObject({ token: "stoken-value", accessToken: "stoken-value", stoken: "stoken-value" });
  });

  test("Wine 注册表写入 REG_BINARY 且保留 null 结尾", async () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-registry-")); roots.push(root);
    const wine = join(root, "wine"), capture = join(root, "args.txt");
    writeFileSync(wine, `#!/bin/sh
if [ "$1" = "ipconfig" ]; then
  printf 'Ethernet adapter anpi0\\n    Physical address. . . . . . . . . : AE-C0-60-E5-94-AE\\n'
  exit 0
fi
printf '%s\\n' "$@" > "$CAPTURE"
`);
    chmodSync(wine, 0o755);

    await writeGameAccountRegistry(wine, { ...process.env, CAPTURE: capture, MHG_GAME_ACCOUNT_MAC: "FC-B2-14-50-82-E5" }, account);
    const args = readFileSync(capture, "utf8").trimEnd().split("\n");
    expect(args).toContain("REG_BINARY");
    const bytes = Buffer.from(args.at(args.indexOf("/d") + 1) ?? "", "hex");
    expect(bytes.at(-1)).toBe(0);
    expect(bytes.subarray(0, -1).toString("utf8")).toMatch(/^[A-Za-z0-9+/]+=*$/);
    const result = decrypt(bytes.subarray(0, -1).toString("utf8"), "FCB21450");
    expect(JSON.parse(result.stdout).data[0].mid).toBe("mid-1");
  });

  test("会话结束恢复原注册表值", async () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-registry-")); roots.push(root);
    const wine = join(root, "wine"), capture = join(root, "calls.txt");
    writeFileSync(wine, `#!/bin/sh
if [ "$2" = "query" ]; then printf 'value REG_BINARY DEADBEEF\n'; exit 0; fi
printf '%s\n' "$@" >> "$CAPTURE"
`); chmodSync(wine, 0o755);
    const env = { ...process.env, CAPTURE: capture, MHG_GAME_ACCOUNT_MAC: "FC-B2-14-50-82-E5" };
    const snapshot = await writeGameAccountRegistry(wine, env, account); await restoreGameAccountRegistry(wine, env, snapshot);
    const calls = readFileSync(capture, "utf8");
    expect(snapshot.value).toBe("DEADBEEF"); expect(calls).toMatch(/\/d\nDEADBEEF\n\/f/);
  });
});

function decrypt(input: string, key: string): { status: number | null; stdout: string } {
  const result = spawnSync("/usr/bin/openssl", ["enc", "-d", "-des-cbc",
    "-K", Buffer.from(key, "utf8").toString("hex"),
    "-iv", "1234567890ABCDEF", "-base64", "-A"], { input, encoding: "utf8" });
  return { status: result.status, stdout: result.stdout };
}
