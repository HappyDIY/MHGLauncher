import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [sourceRoot, outputRoot, cacheRoot, version] = process.argv.slice(2);
if (!sourceRoot || !outputRoot || !cacheRoot || !version) throw new Error("资源构建参数不完整");
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

let cursor = 0;
const entries = [...remoteImages];
async function worker() {
  while (cursor < entries.length) {
    const [name, url] = entries[cursor++];
    const cached = join(cacheRoot, name), destination = join(imageRoot, name);
    try {
      if (!validImage(readFileSync(cached))) throw new Error("缓存插图无效");
      copyFileSync(cached, destination); continue;
    } catch { rmSync(cached, { force: true }); }
    const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
    if (!response.ok) throw new Error(`插图下载失败 ${response.status}: ${url}`);
    const data = Buffer.from(await response.arrayBuffer());
    if (!validImage(data)) throw new Error(`插图格式或大小无效: ${url}`);
    writeFileSync(cached, data); copyFileSync(cached, destination);
  }
}
await Promise.all(Array.from({ length: 8 }, worker));

function validImage(data) {
  if (!data.length || data.length > 50 * 1024 * 1024) return false;
  const hex = data.subarray(0, 12).toString("hex");
  return hex.startsWith("89504e470d0a1a0a") || hex.startsWith("ffd8ff")
    || (hex.startsWith("52494646") && hex.slice(16, 24) === "57454250");
}

const catalog = { schema_version: 1, version, events: catalogEvents, items: catalogItems };
writeFileSync(join(outputRoot, "catalog.json"), `${JSON.stringify(catalog)}\n`);
copyFileSync(join(sourceRoot, "Snap.Metadata.LICENSE"), join(outputRoot, "Snap.Metadata.LICENSE"));
const files = {};
for (const name of ["catalog.json", "Snap.Metadata.LICENSE", ...entries.map(([name]) => `images/${name}`)].sort()) {
  files[name] = createHash("sha256").update(readFileSync(join(outputRoot, name))).digest("hex");
}
writeFileSync(join(outputRoot, "mhg-manifest.json"), `${JSON.stringify({ files })}\n`);
