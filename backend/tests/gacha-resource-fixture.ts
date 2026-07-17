import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export function installGachaResourceFixture(): void {
  const app = globalThis.mhgContainer!;
  const root = join(app.settings.dataDir, "resources", "gacha-history");
  const file = `images/${"a".repeat(64)}.img`;
  mkdirSync(join(root, "images"), { recursive: true });
  writeFileSync(join(root, file), "fixture-image");
  writeFileSync(join(root, ".resource.json"), JSON.stringify({
    installed_bytes: 13, installed_at: "2026-07-18T00:00:00Z",
  }));
  writeFileSync(join(root, "catalog.json"), JSON.stringify({
    schema_version: 1, version: "fixture", items: { "10000096": ["阿蕾奇诺", "角色", 5, file] },
    events: [{
      id: "fixture-event", version: "4.6", gacha_type: "301", name: "炉边烬影",
      started_at: "2024-04-24T06:00:00+08:00", ended_at: "2024-05-14T17:59:00+08:00",
      orange_up: ["阿蕾奇诺"], purple_up: [], banner_file: file,
      updated_at: "2024-05-14T17:59:00+08:00",
    }],
  }));
}
