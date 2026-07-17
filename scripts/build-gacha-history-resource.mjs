import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [sourceRoot, metadataRoot, outputRoot, cacheRoot, version, metadataRevision] = process.argv.slice(2);
if (!sourceRoot || !metadataRoot || !outputRoot || !cacheRoot || !version || !metadataRevision) {
  throw new Error("资源构建参数不完整");
}
const events = JSON.parse(readFileSync(join(sourceRoot, "gacha_events.json"), "utf8"));
const items = JSON.parse(readFileSync(join(sourceRoot, "gacha_items.json"), "utf8"));
const imageRoot = join(outputRoot, "images");
mkdirSync(imageRoot, { recursive: true }); mkdirSync(cacheRoot, { recursive: true });

const remoteImages = new Map();
const imageFile = (url) => {
  if (!url) return null;
  const name = `${createHash("sha256").update(url).digest("hex")}.img`;
  remoteImages.set(name, url); return `images/${name}`;
};
const staticImage = (category, icon) => icon
  ? imageFile(`https://api.snaphutaorp.org/static/raw/${category}/${icon}.png`)
  : null;
const catalogItems = Object.fromEntries(Object.entries(items).map(([id, value]) => {
  const [name, type, rank, icon] = value;
  const kind = type === "角色" ? "AvatarIcon" : "EquipIcon";
  const url = icon ? `https://api.snaphutaorp.org/static/raw/${kind}/${icon}.png` : "";
  return [id, [name, type, rank, imageFile(url) ?? undefined].filter((entry) => entry !== undefined)];
}));
const catalogEvents = events.map((value) => ({
  id: `metadata:${value.Type}:${value.From}:${value.Order}`,
  version: value.Version, gacha_type: String(value.Type), name: value.Name,
  started_at: value.From, ended_at: value.To,
  orange_up: value.UpOrangeList.map((id) => items[String(id)]?.[0] ?? String(id)),
  purple_up: value.UpPurpleList.map((id) => items[String(id)]?.[0] ?? String(id)),
  banner_file: imageFile(value.Banner), updated_at: value.To,
}));

const characterAssets = { avatars: {}, weapons: {}, reliquaries: {}, skills: {}, talents: {} };
const register = (target, id, category, icon) => {
  const file = staticImage(category, icon);
  if (file && id !== undefined && id !== null) target[String(id)] = file;
};
const registerSkill = (target, value) => {
  if (!value) return;
  register(target, value.Id, String(value.Icon ?? "").startsWith("UI_Talent_") ? "Talent" : "Skill", value.Icon);
};
for (const file of readdirSync(join(metadataRoot, "Avatar")).filter((name) => name.endsWith(".json")).sort()) {
  const avatar = JSON.parse(readFileSync(join(metadataRoot, "Avatar", file), "utf8"));
  register(characterAssets.avatars, avatar.Id, "AvatarIcon", avatar.Icon);
  const depot = avatar.SkillDepot ?? {};
  for (const skill of depot.Skills ?? []) registerSkill(characterAssets.skills, skill);
  registerSkill(characterAssets.skills, depot.EnergySkill);
  for (const skill of depot.Inherents ?? []) registerSkill(characterAssets.skills, skill);
  for (const talent of depot.Talents ?? []) registerSkill(characterAssets.talents, talent);
}
for (const [id, icon] of Object.entries({
  10000005: "UI_AvatarIcon_PlayerBoy", 10000007: "UI_AvatarIcon_PlayerGirl",
  10000117: "UI_AvatarIcon_MannequinBoy", 10000118: "UI_AvatarIcon_MannequinGirl",
})) register(characterAssets.avatars, id, "AvatarIcon", icon);
for (const weapon of JSON.parse(readFileSync(join(metadataRoot, "Weapon.json"), "utf8"))) {
  register(characterAssets.weapons, weapon.Id, "EquipIcon", weapon.Icon);
}
for (const relic of JSON.parse(readFileSync(join(metadataRoot, "Reliquary.json"), "utf8"))) {
  for (const id of relic.Ids ?? []) register(characterAssets.reliquaries, id, "RelicIcon", relic.Icon);
}

let cursor = 0;
const entries = [...remoteImages];
const missingImages = new Set();
async function worker() {
  while (cursor < entries.length) {
    const [name, url] = entries[cursor++];
    const cached = join(cacheRoot, name), destination = join(imageRoot, name);
    try {
      if (!validImage(readFileSync(cached))) throw new Error("缓存插图无效");
      copyFileSync(cached, destination); continue;
    } catch { rmSync(cached, { force: true }); }
    const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
    if (response.status === 404) {
      missingImages.add(name);
      process.stderr.write(`跳过上游不存在的素材：${url}\n`);
      continue;
    }
    if (!response.ok) throw new Error(`插图下载失败 ${response.status}: ${url}`);
    const data = Buffer.from(await response.arrayBuffer());
    if (!validImage(data)) throw new Error(`插图格式或大小无效: ${url}`);
    writeFileSync(cached, data); copyFileSync(cached, destination);
  }
}
await Promise.all(Array.from({ length: 8 }, worker));

for (const value of Object.values(catalogItems)) {
  if (value[3] && missingImages.has(value[3].slice("images/".length))) value.splice(3, 1);
}
for (const value of catalogEvents) {
  if (value.banner_file && missingImages.has(value.banner_file.slice("images/".length))) value.banner_file = null;
}
for (const values of Object.values(characterAssets)) {
  for (const [id, file] of Object.entries(values)) {
    if (missingImages.has(file.slice("images/".length))) delete values[id];
  }
}
const includedEntries = entries.filter(([name]) => !missingImages.has(name));

function validImage(data) {
  if (!data.length || data.length > 50 * 1024 * 1024) return false;
  const hex = data.subarray(0, 12).toString("hex");
  return hex.startsWith("89504e470d0a1a0a") || hex.startsWith("ffd8ff")
    || (hex.startsWith("52494646") && hex.slice(16, 24) === "57454250");
}

const catalog = {
  schema_version: 2, version, metadata_revision: metadataRevision,
  events: catalogEvents, items: catalogItems, character_assets: characterAssets,
};
writeFileSync(join(outputRoot, "catalog.json"), `${JSON.stringify(catalog)}\n`);
copyFileSync(join(sourceRoot, "Snap.Metadata.LICENSE"), join(outputRoot, "Snap.Metadata.LICENSE"));
const files = {};
for (const name of ["catalog.json", "Snap.Metadata.LICENSE", ...includedEntries.map(([name]) => `images/${name}`)].sort()) {
  files[name] = createHash("sha256").update(readFileSync(join(outputRoot, name))).digest("hex");
}
writeFileSync(join(outputRoot, "mhg-manifest.json"), `${JSON.stringify({ files })}\n`);
