import { randomUUID } from "node:crypto";
import {
  existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync,
} from "node:fs";
import { basename, join } from "node:path";
import { z } from "zod";
import { AppError } from "../core/errors";
import type { GameCharacter, GachaEvent, GachaResourceStatus, WishRecord } from "../core/models";
import { localizeCharacter } from "./character-resource-enrichment";
import { DownloadControl, hash } from "./download";
import { streamDownload } from "./download-transfer";
import { activate, extract, safeTarget, verify } from "./installer";
import { catalogFiles, readCatalog, resourceFile, type Catalog, type Metadata } from "./gacha-resource-catalog";
import { ImageResourceCache } from "./image-resource-cache";
const remoteManifestSchema = z.object({
  schema_version: z.literal(1), version: z.string().min(1).max(64),
  archive: z.object({
    url: z.string().min(1).max(2_048), size: z.number().int().positive().max(2_000_000_000),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
  }).strict(),
}).strict();

export class GachaResourceService {
  private readonly destination: string;
  private readonly imageCache: ImageResourceCache;
  private catalogCache?: Catalog;
  private installing = false;

  constructor(private readonly dataDir: string, private readonly manifestUrl?: string) {
    this.destination = join(dataDir, "resources", "gacha-history");
    this.imageCache = new ImageResourceCache(dataDir);
  }

  status(): GachaResourceStatus {
    const catalog = this.catalog(false), descriptor = this.descriptor();
    return {
      state: this.installing ? "installing" : catalog ? "ready" : "missing",
      version: catalog?.version ?? null, event_count: catalog?.events.length ?? 0,
      image_count: catalog ? new Set(this.files(catalog)).size : 0,
      installed_bytes: Number(descriptor?.installed_bytes ?? 0),
      installed_at: typeof descriptor?.installed_at === "string" ? descriptor.installed_at : null,
    };
  }

  events(): GachaEvent[] {
    const catalog = this.catalog(true)!;
    return catalog.events.map(({ banner_file, ...value }) => ({
      ...value, banner_url: banner_file ? this.endpoint(banner_file, catalog.version) : null,
      orange_up_icons: this.iconURLs(value.orange_up, catalog),
      purple_up_icons: this.iconURLs(value.purple_up, catalog),
    }));
  }

  enrich(record: WishRecord): WishRecord {
    const catalog = this.catalog(false);
    if (!catalog) return { ...record, icon_url: null };
    let id = record.item_id, metadata = catalog.items[id];
    if (!metadata && record.name) {
      const match = Object.entries(catalog.items).find(([, value]) => value[0] === record.name);
      if (match) [id, metadata] = match;
    }
    if (!metadata) return { ...record, icon_url: null };
    return {
      ...record, item_id: id, name: record.name || metadata[0], item_type: record.item_type || metadata[1],
      rank: record.rank || metadata[2], icon_url: metadata[3] ? this.endpoint(metadata[3], catalog.version) : null,
    };
  }

  enrichCharacter(character: GameCharacter): GameCharacter {
    const catalog = this.catalog(false);
    return localizeCharacter(
      character, catalog, (name) => this.endpoint(name, catalog?.version ?? "missing"),
      (remote) => this.imageCache.localURL(remote),
    );
  }

  async cacheCharacters(characters: GameCharacter[]): Promise<void> {
    await this.imageCache.ensureCharacters(characters);
  }

  cachedFile(name: string): Buffer | null { return this.imageCache.file(name); }

  file(name: string): Buffer | null {
    if (!resourceFile.safeParse(name).success) return null;
    const path = safeTarget(this.destination, name);
    return existsSync(path) ? readFileSync(path) : null;
  }

  async install(): Promise<GachaResourceStatus> {
    if (this.installing) throw new AppError("gacha_resource_busy", "历史卡池资源正在下载", 409);
    if (!this.manifestUrl) throw new AppError("gacha_resource_unavailable", "历史卡池资源地址未配置", 503);
    this.installing = true;
    try { await this.installResource(); }
    finally { this.installing = false; }
    return this.status();
  }

  private async installResource(): Promise<void> {
    const manifest = await this.remoteManifest(), root = join(this.dataDir, "resources");
    mkdirSync(root, { recursive: true, mode: 0o700 });
    const archive = join(root, "gacha-history-download.zip");
    const staging = join(root, `gacha-history.mhg-staging-${randomUUID()}`);
    rmSync(archive, { force: true }); rmSync(`${archive}.part`, { force: true });
    try {
      const archiveUrl = this.archiveURL(manifest.archive.url);
      await streamDownload(archiveUrl, `${archive}.part`, manifest.archive.size, basename(archive), new DownloadControl(), () => undefined);
      if (hash(`${archive}.part`, "sha256") !== manifest.archive.sha256) {
        throw new AppError("gacha_resource_hash_mismatch", "历史卡池资源校验失败", 502);
      }
      renameSync(`${archive}.part`, archive); extract([archive], staging); verify(staging);
      const catalog = readCatalog(staging);
      if (catalog.version !== manifest.version) throw new AppError("gacha_resource_version_mismatch", "历史卡池资源版本不一致", 502);
      writeFileSync(join(staging, ".resource.json"), JSON.stringify({
        installed_bytes: manifest.archive.size, installed_at: new Date().toISOString(),
      }));
      activate(staging, this.destination); this.catalogCache = catalog;
    } finally {
      rmSync(archive, { force: true }); rmSync(`${archive}.part`, { force: true });
      rmSync(staging, { recursive: true, force: true });
    }
  }

  private async remoteManifest(): Promise<z.infer<typeof remoteManifestSchema>> {
    const response = await fetch(this.manifestUrl!, { signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new AppError("gacha_resource_manifest_failed", `历史卡池资源清单下载失败：${response.status}`, 502);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length > 1024 * 1024) throw new AppError("gacha_resource_manifest_invalid", "历史卡池资源清单过大", 502);
    try { return remoteManifestSchema.parse(JSON.parse(Buffer.from(bytes).toString("utf8"))); }
    catch { throw new AppError("gacha_resource_manifest_invalid", "历史卡池资源清单无效", 502); }
  }

  private catalog(required: boolean): Catalog | undefined {
    if (!this.catalogCache && existsSync(join(this.destination, "catalog.json"))) {
      try { this.catalogCache = readCatalog(this.destination); }
      catch (error) { if (required) throw error; }
    }
    if (required && !this.catalogCache) throw new AppError("gacha_resource_missing", "请先下载历史卡池资源", 409);
    return this.catalogCache;
  }

  private files(catalog: Catalog): string[] {
    return catalogFiles(catalog);
  }

  private iconURLs(names: string[], catalog: Catalog): Record<string, string> {
    const byName = new Map<string, Metadata>(Object.values(catalog.items).map((value) => [value[0], value]));
    return Object.fromEntries(names.flatMap((name) => byName.get(name)?.[3]
      ? [[name, this.endpoint(byName.get(name)![3]!, catalog.version)]] : []));
  }

  private endpoint(name: string, version: string): string {
    return `/v1/gacha-resources/files/${name}?version=${encodeURIComponent(version)}`;
  }
  private archiveURL(value: string): string {
    const manifest = new URL(this.manifestUrl!), url = new URL(value, manifest);
    if (url.protocol !== "https:" || url.origin !== manifest.origin || url.username || url.password) {
      throw new AppError("gacha_resource_archive_url_invalid", "历史卡池资源包地址无效", 502);
    }
    return url.href;
  }
  private descriptor(): Record<string, unknown> | undefined {
    try { return JSON.parse(readFileSync(join(this.destination, ".resource.json"), "utf8")) as Record<string, unknown>; }
    catch { return undefined; }
  }
}
