import { existsSync, readFileSync } from "node:fs";
import { z } from "zod";
import { AppError } from "../core/errors";
import { safeTarget } from "./installer";

export const resourceFile = z.string().regex(/^images\/[a-f0-9]{64}\.img$/);
const item = z.tuple([z.string(), z.string(), z.number().int(), resourceFile.optional()]);
const event = z.object({
  id: z.string(), version: z.string(), gacha_type: z.string(), name: z.string(),
  started_at: z.string().nullable(), ended_at: z.string().nullable(),
  orange_up: z.array(z.string()), purple_up: z.array(z.string()),
  banner_file: resourceFile.nullable(), updated_at: z.string(),
}).strict();
const assetMap = z.record(z.string(), resourceFile).refine((value) => Object.keys(value).length <= 20_000);
const characterAssets = z.object({
  avatars: assetMap, weapons: assetMap, reliquaries: assetMap,
  skills: assetMap, talents: assetMap,
}).strict();

const catalogSchema = z.object({
  schema_version: z.literal(2), version: z.string().min(1).max(64),
  metadata_revision: z.string().min(1).max(64),
  events: z.array(event).max(10_000), items: z.record(z.string(), item),
  character_assets: characterAssets,
}).strict();

export type Catalog = z.infer<typeof catalogSchema>;
export type CharacterAssetKind = keyof Catalog["character_assets"];
export type Metadata = z.infer<typeof item>;

export function readCatalog(root: string): Catalog {
  try {
    const value = catalogSchema.parse(JSON.parse(readFileSync(`${root}/catalog.json`, "utf8")));
    for (const name of catalogFiles(value)) {
      if (!existsSync(safeTarget(root, name))) throw new Error(name);
    }
    return value;
  } catch {
    throw new AppError("gacha_resource_invalid", "完整素材资源已损坏，请重新下载", 409);
  }
}

export function catalogFiles(catalog: Catalog): string[] {
  return [
    ...catalog.events.flatMap(({ banner_file }) => banner_file ? [banner_file] : []),
    ...Object.values(catalog.items).flatMap((value) => value[3] ? [value[3]] : []),
    ...Object.values(catalog.character_assets).flatMap((values) => Object.values(values)),
  ];
}
