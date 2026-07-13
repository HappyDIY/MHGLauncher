import { spawnSync } from "node:child_process";
import { networkInterfaces } from "node:os";
import type { Account } from "../core/models";
import { AppError } from "../core/errors";
import { cookies } from "../providers/signing";

const iv = "1234567890ABCDEF";
const registryKey = "HKCU\\Software\\miHoYo\\原神";
const registryValue = "MIHOYOSDK_ADL_PROD_CN_h3123967166";

export interface RegistryAccount {
  aid: string; mid: string; nickname: string; credential: string;
}
export interface RegistrySnapshot { value: string | null }

export function writeGameAccountRegistry(wine: string, env: NodeJS.ProcessEnv, account: RegistryAccount): RegistrySnapshot {
  const snapshot = readGameAccountRegistry(wine, env);
  const raw = createGameAccountRegistryValue(account, cleanMac(env.MHG_GAME_ACCOUNT_MAC ?? "") || macAddress() || wineMacAddress(wine, env));
  const hex = Buffer.concat([Buffer.from(raw, "utf8"), Buffer.from([0])]).toString("hex");
  const result = spawnSync(wine, ["reg", "add", registryKey, "/v", registryValue, "/t", "REG_BINARY", "/d", hex, "/f"], {
    env, stdio: "ignore",
  });
  if (result.status !== 0) throw new AppError("game_account_registry_failed", "游戏账号写入 Wine 注册表失败", 500);
  return snapshot;
}

export function restoreGameAccountRegistry(wine: string, env: NodeJS.ProcessEnv, snapshot: RegistrySnapshot): void {
  const args = snapshot.value
    ? ["reg", "add", registryKey, "/v", registryValue, "/t", "REG_BINARY", "/d", snapshot.value, "/f"]
    : ["reg", "delete", registryKey, "/v", registryValue, "/f"];
  spawnSync(wine, args, { env, stdio: "ignore" });
}

export function launchAccount(account: Account, credential: string): RegistryAccount {
  return { aid: account.aid, mid: account.mid, nickname: account.nickname, credential };
}

export function createGameAccountRegistryValue(account: RegistryAccount, mac = macAddress(), now = Math.floor(Date.now() / 1000)): string {
  return mihoyoSdk(account, mac, now);
}

function mihoyoSdk(account: RegistryAccount, mac: string, now: number): string {
  const map = cookies(account.credential);
  const cookieToken = map.get("cookie_token") ?? map.get("ltoken") ?? map.get("stoken") ?? "";
  const sToken = map.get("stoken") ?? map.get("ltoken") ?? cookieToken;
  const data = {
    data: [{
      uid: account.aid, mid: account.mid, name: account.nickname, email: "", mobile: "",
      is_email_verify: false, realname: "", identity_card: "", token_type: 1,
      token: cookieToken, stoken: sToken, is_guest: false, guest_id: "", safe_mobile: "",
      account: account.aid, is_login: true, login_type: 1, payload: "",
      channel_id: 1, asterisk_name: account.nickname, accessToken: cookieToken,
      deviceId: "", country: "CN", area_code: "+86", reactivate_ticket: "",
      device_grant_ticket: "", thirdLoginTimestamp: now, account_display_type: "1",
      imageName: "", loginPattern: 1, loginTime: now, agreeSaveAccount: true,
      emailLastLogin: false, authTicketThirdParty: 0, links: [],
      agree_persistent_login_data: true,
    }],
  };
  return encrypt(JSON.stringify(data), mac);
}

function readGameAccountRegistry(wine: string, env: NodeJS.ProcessEnv): RegistrySnapshot {
  const result = spawnSync(wine, ["reg", "query", registryKey, "/v", registryValue], { env, encoding: "utf8" });
  const match = result.status === 0 ? result.stdout.match(/REG_BINARY\s+([0-9a-f]+)/i) : null;
  return { value: match?.[1] ?? null };
}

function encrypt(value: string, mac: string): string {
  const key = Buffer.from((mac.length >= 8 ? mac.slice(0, 8) : "FFFFFFFFFFFF").slice(0, 8), "utf8").toString("hex");
  const args = ["enc", "-des-cbc", "-K", key, "-iv", iv, "-base64", "-A"];
  const errors: string[] = [];
  for (const command of ["/usr/bin/openssl", "/opt/homebrew/bin/openssl", "openssl"]) {
    const extra = command === "/usr/bin/openssl" ? [] : ["-provider", "legacy", "-provider", "default"];
    const result = spawnSync(command, [...args.slice(0, 2), ...extra, ...args.slice(2)], { input: value, encoding: "utf8" });
    if (result.status === 0 && result.stdout.trim()) return result.stdout.trim();
    errors.push(`${command}: ${result.error?.message ?? result.stderr.trim() ?? `status ${result.status}`}`);
  }
  throw new AppError("game_account_encrypt_failed", "游戏账号注册表数据加密失败", 500, { openssl: errors.join("; ") });
}

function macAddress(): string {
  for (const command of [["/usr/sbin/networksetup", "-listallhardwareports"], ["/sbin/ifconfig", "en0"]] as const) {
    const result = spawnSync(command[0], command.slice(1), { encoding: "utf8" });
    const match = result.stdout.match(/(?:Ethernet Address|ether)\s+([0-9a-fA-F:]{17})/);
    const value = match ? cleanMac(match[1] ?? "") : "";
    if (validMac(value)) return value;
  }
  for (const items of Object.values(networkInterfaces())) {
    for (const item of items ?? []) {
      const value = cleanMac(item.mac);
      if (!item.internal && validMac(value)) return value;
    }
  }
  return "";
}

function wineMacAddress(wine: string, env: NodeJS.ProcessEnv): string {
  const result = spawnSync(wine, ["ipconfig", "/all"], { env, encoding: "utf8" });
  if (result.status !== 0) return "";
  const matches = result.stdout.matchAll(/Physical address[^:]*:\s*([0-9a-fA-F-]{17})/g);
  for (const match of matches) {
    const value = cleanMac(String(match[1]));
    if (validMac(value)) return value;
  }
  return "";
}

function cleanMac(value: string): string {
  return value.replaceAll(/[:-]/g, "").toUpperCase();
}

function validMac(value: string): boolean {
  return /^[0-9A-F]{12}$/.test(value) && value !== "000000000000" && value !== "020000000000";
}
