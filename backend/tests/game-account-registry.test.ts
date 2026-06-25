import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { createGameAccountRegistryValue, writeGameAccountRegistry, type RegistryAccount } from "../src/services/game-account-registry";

const roots: string[] = [];
const account: RegistryAccount = { aid: "10001", mid: "mid-1", nickname: "旅行者", credential: "stoken=stoken-value; mid=mid-1" };

afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("游戏账号注册表", () => {
  test("SDK 字符串可用源项目 DES-CBC 规则解密", () => {
    const mac = "A1B2C3D4E5F6";
    const sdk = createGameAccountRegistryValue(account, mac, 1_700_000_000);
    const result = spawnSync("openssl", ["enc", "-d", "-des-cbc", "-provider", "legacy", "-provider", "default",
      "-K", Buffer.from(mac.slice(0, 8), "utf8").toString("hex"), "-iv", "1234567890ABCDEF", "-base64", "-A"], {
      input: sdk, encoding: "utf8",
    });
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout).data[0]).toMatchObject({
      uid: "10001", mid: "mid-1", token: "stoken-value", stoken: "stoken-value", is_login: true,
      thirdLoginTimestamp: 1_700_000_000, loginTime: 1_700_000_000,
    });
  });

  test("Wine 注册表写入 REG_BINARY 且保留 null 结尾", () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-registry-")); roots.push(root);
    const wine = join(root, "wine"), capture = join(root, "args.txt");
    writeFileSync(wine, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CAPTURE\"\n");
    chmodSync(wine, 0o755);

    writeGameAccountRegistry(wine, { ...process.env, CAPTURE: capture }, account);
    const args = readFileSync(capture, "utf8").trimEnd().split("\n");
    expect(args).toContain("REG_BINARY");
    const bytes = Buffer.from(args.at(args.indexOf("/d") + 1) ?? "", "hex");
    expect(bytes.at(-1)).toBe(0);
    expect(bytes.subarray(0, -1).toString("utf8")).toMatch(/^[A-Za-z0-9+/]+=*$/);
  });
});
