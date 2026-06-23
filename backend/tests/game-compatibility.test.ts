import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { ensureGameConfiguration } from "../src/services/game-config";
import { patchGeneralData } from "../src/services/game-launch-language";

test("创建与胡桃一致的国服游戏配置", () => {
  const root = mkdtempSync(join(tmpdir(), "game-config-"));
  ensureGameConfiguration(root, "6.6.0");
  const content = readFileSync(join(root, "config.ini"), "utf8");
  expect(content).toContain("channel=1");
  expect(content).toContain("sub_channel=1");
  expect(content).toContain("game_version=6.6.0");
  ensureGameConfiguration(root, "6.7.0");
  expect(readFileSync(join(root, "config.ini"), "utf8")).toContain("game_version=6.7.0");
});

test("保留游戏设置并统一文字与语音为简体中文", () => {
  const original = { deviceLanguageType: 1, deviceVoiceLanguageType: 1, selectedServerName: "cn_gf01" };
  const hex = Buffer.from(`${JSON.stringify(original)}\0`).toString("hex");
  const patched = JSON.parse(Buffer.from(patchGeneralData(hex), "hex").toString("utf8").replace(/\0+$/, "")) as Record<string, unknown>;
  expect(patched).toMatchObject({ deviceLanguageType: 0, deviceVoiceLanguageType: 0, selectedServerName: "cn_gf01" });
});

test("更新现有配置时保留渠道字段", () => {
  const root = mkdtempSync(join(tmpdir(), "game-config-existing-"));
  writeFileSync(join(root, "config.ini"), "[general]\nchannel=14\ngame_version=6.5.0\n");
  ensureGameConfiguration(root, "6.6.0");
  expect(readFileSync(join(root, "config.ini"), "utf8")).toBe("[general]\nchannel=14\ngame_version=6.6.0\n");
});
