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

export function writeGameAccountRegistry(wine: string, env: NodeJS.ProcessEnv, account: RegistryAccount): void {
  const raw = createGameAccountRegistryValue(account);
  const hex = Buffer.concat([Buffer.from(raw, "utf8"), Buffer.from([0])]).toString("hex");
  const result = spawnSync(wine, ["reg", "add", registryKey, "/v", registryValue, "/t", "REG_BINARY", "/d", hex, "/f"], {
    env, stdio: "ignore",
  });
  if (result.status !== 0) throw new AppError("game_account_registry_failed", "游戏账号写入 Wine 注册表失败", 500);
}

export function launchAccount(account: Account, credential: string): RegistryAccount {
  return { aid: account.aid, mid: account.mid, nickname: account.nickname, credential };
}

export function createGameAccountRegistryValue(account: RegistryAccount, mac = macAddress(), now = Math.floor(Date.now() / 1000)): string {
  return mihoyoSdk(account, mac, now);
}

function mihoyoSdk(account: RegistryAccount, mac: string, now: number): string {
  const map = cookies(account.credential);
  const token = map.get("stoken") ?? map.get("ltoken") ?? "";
  const data = {
    data: [{
      uid: account.aid, mid: account.mid, name: account.nickname, email: "", mobile: "",
      is_email_verify: false, realname: "", identity_card: "", token_type: 1,
      token, stoken: token, is_guest: false, guest_id: "", safe_mobile: "",
      account: account.aid, is_login: true, login_type: 1, payload: "",
      channel_id: 1, asterisk_name: account.nickname, accessToken: token,
      deviceId: "", country: "CN", area_code: "+86", reactivate_ticket: "",
      device_grant_ticket: "", thirdLoginTimestamp: now, account_display_type: "1",
      imageName: "", loginPattern: 1, loginTime: now, agreeSaveAccount: true,
      emailLastLogin: false, authTicketThirdParty: 0, links: [],
      agree_persistent_login_data: true,
    }],
  };
  return encrypt(JSON.stringify(data), mac);
}

function encrypt(value: string, mac: string): string {
  const key = Buffer.from((mac.length >= 8 ? mac.slice(0, 8) : "FFFFFFFFFFFF").slice(0, 8), "utf8").toString("hex");
  const result = spawnSync("openssl", ["enc", "-des-cbc", "-provider", "legacy", "-provider", "default", "-K", key, "-iv", iv, "-base64", "-A"], {
    input: value, encoding: "utf8",
  });
  if (result.status !== 0 || !result.stdout.trim()) throw new AppError("game_account_encrypt_failed", "游戏账号注册表数据加密失败", 500);
  return result.stdout.trim();
}

function macAddress(): string {
  for (const items of Object.values(networkInterfaces())) {
    for (const item of items ?? []) {
      const value = item.mac.replaceAll(":", "").toUpperCase();
      if (!item.internal && value && value !== "000000000000") return value;
    }
  }
  return "";
}
