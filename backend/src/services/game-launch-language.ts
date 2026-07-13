import { AppError } from "../core/errors";
import { runCommand } from "./process-command";

const GAME_KEY = "HKCU\\Software\\miHoYo\\原神";
const GENERAL_DATA = "GENERAL_DATA_h2389025596";
const SDK_LANGUAGE = "MIHOYOSDK_CURRENT_LANGUAGE_h2559149783";

export async function configureChineseGameLanguage(wine: string, env: NodeJS.ProcessEnv): Promise<void> {
  const query = await runCommand(wine, ["reg", "query", GAME_KEY, "/v", GENERAL_DATA], { env });
  if (query.status === 0) {
    const hex = query.stdout.match(/REG_BINARY\s+([0-9a-f]+)/i)?.[1];
    if (hex) await writeBinary(wine, env, GENERAL_DATA, patchGeneralData(hex));
  }
  await writeBinary(wine, env, SDK_LANGUAGE, Buffer.from("zh-cn\0").toString("hex"));
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

async function writeBinary(wine: string, env: NodeJS.ProcessEnv, name: string, hex: string): Promise<void> {
  const result = await runCommand(wine, ["reg", "add", GAME_KEY, "/v", name, "/t", "REG_BINARY", "/d", hex, "/f"], { env });
  if (result.status !== 0) throw new AppError("game_language_write_failed", "无法写入游戏简体中文语言配置", 500);
}
