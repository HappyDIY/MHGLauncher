import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";

const GAME_KEY = "HKCU\\Software\\miHoYo\\原神";
const GENERAL_DATA = "GENERAL_DATA_h2389025596";
const SDK_LANGUAGE = "MIHOYOSDK_CURRENT_LANGUAGE_h2559149783";

export function configureChineseGameLanguage(wine: string, env: NodeJS.ProcessEnv): void {
  const query = spawnSync(wine, ["reg", "query", GAME_KEY, "/v", GENERAL_DATA], { env, encoding: "utf8" });
  if (query.status === 0) {
    const hex = query.stdout.match(/REG_BINARY\s+([0-9a-f]+)/i)?.[1];
    if (hex) writeBinary(wine, env, GENERAL_DATA, patchGeneralData(hex));
  }
  writeBinary(wine, env, SDK_LANGUAGE, Buffer.from("zh-cn\0").toString("hex"));
}

export function patchGeneralData(hex: string): string {
  try {
    const source = Buffer.from(hex, "hex").toString("utf8").replace(/\0+$/, "");
    const value = JSON.parse(source) as Record<string, unknown>;
    value.deviceLanguageType = 0;
    value.deviceVoiceLanguageType = 0;
    return Buffer.from(`${JSON.stringify(value)}\0`).toString("hex");
  } catch {
    throw new AppError("game_language_data_invalid", "游戏语言配置已损坏，无法安全切换为简体中文", 409);
  }
}

function writeBinary(wine: string, env: NodeJS.ProcessEnv, name: string, hex: string): void {
  const result = spawnSync(wine, ["reg", "add", GAME_KEY, "/v", name, "/t", "REG_BINARY", "/d", hex, "/f"], {
    env, stdio: "ignore",
  });
  if (result.status !== 0) throw new AppError("game_language_write_failed", "无法写入游戏简体中文语言配置", 500);
}
