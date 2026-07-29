import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { GameCharacter, GachaEvent, GachaResourceStatus, WishRecord } from "../core/models";
import { AppError } from "../core/errors";
import { safeTarget } from "./installer";
import { readCatalog, resourceFile, type Catalog } from "./gacha-resource-catalog";
import { ImageResourceCache } from "./image-resource-cache";
import type { MetadataRepository, ResourceStatus } from "./metadata-repository";
import type { MetadataSnapshot, SnapAssets } from "./snap-metadata";
import { localizeCharacter } from "./character-resource-enrichment";

type JSONObject = Record<string, unknown>;
const assetCategory: Record<keyof SnapAssets, string> = {
  avatars: "AvatarIcon", weapons: "EquipIcon", reliquaries: "RelicIcon", skills: "Skill", talents: "Talent",
};

export class GachaResourceService {
  private readonly legacyRoot: string;
  private readonly imageCache: ImageResourceCache;
  private legacyCache?: Catalog;

  constructor(
    dataDir: string,
    private readonly repository: MetadataRepository,
    apiBaseUrl: string,
    networkEnabled = true,
    imageCache?: ImageResourceCache,
  ) {
    this.legacyRoot = join(dataDir, "resources", "gacha-history");
    this.imageCache = imageCache ?? new ImageResourceCache(dataDir, apiBaseUrl, networkEnabled);
  }

  resourceStatus(): ResourceStatus { return this.repository.status(); }

  status(): GachaResourceStatus {
    const current = this.repository.status(), snapshot = this.repository.snapshot(), legacy = this.legacy(false);
    return {
      state: snapshot || legacy ? "ready" : current.state === "syncing" ? "installing" : "missing",
      version: snapshot?.oid ?? legacy?.version ?? null,
      event_count: snapshot?.events.length ?? legacy?.events.length ?? 0,
      image_count: snapshot ? this.imageCount(snapshot) : legacy ? new Set(this.legacyFiles(legacy)).size : 0,
      installed_bytes: 0, installed_at: snapshot?.activatedAt ?? null,
    };
  }

  async install(force = true): Promise<GachaResourceStatus> {
    await this.repository.sync(force);
    return this.status();
  }

  async events(): Promise<GachaEvent[]> {
    const snapshot = await this.repository.ensure();
    return snapshot ? this.snapshotEvents(snapshot) : this.legacyEvents();
  }

  currentEvents(): GachaEvent[] {
    const snapshot = this.repository.snapshot();
    return snapshot ? this.snapshotEvents(snapshot) : this.legacy(false) ? this.legacyEvents() : [];
  }

  private snapshotEvents(snapshot: MetadataSnapshot): GachaEvent[] {
    return snapshot.events.map((event) => {
      const names = (ids: number[]) => ids.flatMap((id) => snapshot.items[String(id)]?.name ?? []);
      const orange = names(event.orange), purple = names(event.purple);
      return {
        id: `${event.version}-${event.order}-${event.type}-${event.name}`, version: event.version,
        gacha_type: String(event.type), name: event.name, started_at: event.from, ended_at: event.to,
        orange_up: orange, purple_up: purple, updated_at: event.to,
        banner_url: this.imageCache.localURL(event.banner, snapshot.oid),
        orange_up_icons: this.gachaIcons(event.orange, snapshot),
        purple_up_icons: this.gachaIcons(event.purple, snapshot),
      };
    });
  }

  enrich(record: WishRecord): WishRecord {
    const snapshot = this.repository.snapshot();
    if (!snapshot) return this.legacyEnrich(record);
    let id = record.item_id, item = snapshot.items[id];
    if (!item && record.name) {
      const match = Object.entries(snapshot.items).find(([, value]) => value.name === record.name);
      if (match) [id, item] = match;
    }
    if (!item) return { ...record, icon_url: null };
    const category = item.kind === "角色" ? "AvatarIcon" : "EquipIcon";
    return { ...record, item_id: id, name: record.name || item.name, item_type: record.item_type || item.kind,
      rank: record.rank || item.rank, icon_url: this.imageCache.namedURL(category, item.icon, item.digest) };
  }

  enrichCharacter(character: GameCharacter): GameCharacter {
    const snapshot = this.repository.snapshot();
    if (!snapshot) return this.legacyCharacter(character);
    const payload = clone(character.payload);
    this.localizeImages(payload);
    const rewrite = (value: unknown, kind: keyof SnapAssets, key: string) => {
      const object = asObject(value), id = object?.[key];
      const asset = id === undefined ? undefined : snapshot.assets[kind][String(id)];
      if (object) object.icon = asset ? this.imageCache.namedURL(assetCategory[kind], asset[0], asset[1]) : null;
    };
    rewrite(payload, "avatars", "id"); rewrite(asObject(payload)?.base, "avatars", "id");
    rewrite(asObject(payload)?.weapon, "weapons", "id"); rewrite(asObject(asObject(payload)?.base)?.weapon, "weapons", "id");
    rewriteList(asObject(payload)?.relics, (value) => rewrite(value, "reliquaries", "id"));
    rewriteList(asObject(payload)?.skills, (value) => rewrite(value, "skills", "skill_id"));
    rewriteList(asObject(payload)?.constellations, (value) => rewrite(value, "talents", "id"));
    const avatar = snapshot.assets.avatars[character.avatar_id];
    return { ...character, payload, icon_url: avatar
      ? this.imageCache.namedURL("AvatarIcon", avatar[0], avatar[1])
      : this.imageCache.localURL(character.icon_url) };
  }

  async cacheCharacters(characters: GameCharacter[]): Promise<void> { await this.imageCache.ensureCharacters(characters); }
  cachedFile(name: string): Buffer | null { return this.imageCache.file(name); }
  async fetchCachedFile(name: string): Promise<Buffer | null> { return this.imageCache.fetchFile(name); }

  async file(name: string): Promise<Buffer | null> {
    if (resourceFile.safeParse(name).success) {
      const path = safeTarget(this.legacyRoot, name);
      if (existsSync(path)) return readFileSync(path);
    }
    return null;
  }

  private gachaIcons(ids: number[], snapshot: MetadataSnapshot): Record<string, string> {
    return Object.fromEntries(ids.flatMap((id) => {
      const item = snapshot.items[String(id)];
      if (!item) return [];
      const category = item.kind === "角色" ? "AvatarIcon" : "EquipIcon";
      const url = this.imageCache.namedURL(category, item.icon, item.digest);
      return url ? [[item.name, url]] : [];
    }));
  }
  private imageCount(snapshot: MetadataSnapshot): number {
    return Object.values(snapshot.assets).reduce((total, values) => total + Object.keys(values).length, 0);
  }
  private localizeImages(value: unknown): void {
    if (Array.isArray(value)) return value.forEach((item) => this.localizeImages(item));
    const object = asObject(value);
    if (!object) return;
    for (const [key, child] of Object.entries(object)) {
      if (["icon", "image", "side_icon"].includes(key)) {
        object[key] = typeof child === "string" ? this.imageCache.localURL(child) : null;
      } else {
        this.localizeImages(child);
      }
    }
  }
  private legacy(required: boolean): Catalog | undefined {
    if (!this.legacyCache && existsSync(join(this.legacyRoot, "catalog.json"))) {
      try { this.legacyCache = readCatalog(this.legacyRoot); } catch { /* 使用缺失状态。 */ }
    }
    if (required && !this.legacyCache) throw new AppError("gacha_resource_missing", "暂无可用游戏资料，请刷新后重试", 409);
    return this.legacyCache;
  }
  private legacyEvents(): GachaEvent[] {
    const catalog = this.legacy(true)!;
    return catalog.events.map(({ banner_file, ...event }) => ({ ...event,
      banner_url: banner_file ? this.legacyEndpoint(banner_file, catalog.version) : null }));
  }
  private legacyEnrich(record: WishRecord): WishRecord {
    const catalog = this.legacy(false), item = catalog?.items[record.item_id];
    return item ? { ...record, name: record.name || item[0], item_type: record.item_type || item[1],
      rank: record.rank || item[2], icon_url: item[3] ? this.legacyEndpoint(item[3], catalog!.version) : null }
      : { ...record, icon_url: null };
  }
  private legacyCharacter(value: GameCharacter): GameCharacter {
    const catalog = this.legacy(false);
    return localizeCharacter(
      value, catalog, (name) => this.legacyEndpoint(name, catalog?.version ?? "legacy"),
      (remote) => this.imageCache.localURL(remote),
    );
  }
  private legacyFiles(catalog: Catalog): string[] {
    return [...catalog.events.flatMap(({ banner_file }) => banner_file ? [banner_file] : []),
      ...Object.values(catalog.items).flatMap((item) => item[3] ? [item[3]] : [])];
  }
  private legacyEndpoint(name: string, version: string): string {
    return `/v1/gacha-resources/files/${name}?version=${encodeURIComponent(version)}`;
  }
}

function clone(value: unknown): JSONObject | undefined {
  const object = asObject(value); return object ? structuredClone(object) : undefined;
}
function asObject(value: unknown): JSONObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JSONObject : undefined;
}
function rewriteList(value: unknown, rewrite: (value: unknown) => void): void {
  if (Array.isArray(value)) value.forEach(rewrite);
}
