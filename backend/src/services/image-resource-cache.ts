import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { GameCharacter } from "../core/models";
import { AppError } from "../core/errors";
import { readBoundedBody } from "./http-response";

const imageName = /^[a-f0-9]{64}\.img$/;
const imageKeys = new Set(["icon", "image", "side_icon"]);
const namedImage = /^[A-Za-z0-9_]{1,128}$/;
const categories = new Set([
  "AvatarIcon", "EquipIcon", "RelicIcon", "Skill", "Talent",
  "AchievementIcon", "GachaAvatarIcon", "GachaAvatarImg",
]);
type CacheIndex = Record<string, { url: string; digest: string }>;

export class ImageResourceCache {
  private readonly root: string;
  private readonly indexPath: string;
  private readonly index: CacheIndex;
  private readonly pending = new Map<string, Promise<void>>();

  constructor(
    dataDir: string,
    private readonly apiBaseUrl = "https://api.snaphutaorp.org",
    private readonly networkEnabled = true,
  ) {
    this.root = join(dataDir, "resources", "image-cache");
    this.indexPath = join(this.root, "index.json");
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
    this.index = this.readIndex();
  }

  async ensureCharacters(characters: GameCharacter[]): Promise<void> {
    const urls = [...new Set(characters.flatMap((value) => [
      ...this.imageURLs(value.payload), ...(value.icon_url ? [value.icon_url] : []),
    ]))];
    let cursor = 0;
    const worker = async () => {
      while (cursor < urls.length) await this.ensure(urls[cursor++]!);
    };
    await Promise.all(Array.from({ length: Math.min(8, urls.length) }, worker));
  }

  localURL(remote: string | null | undefined, digest = "upstream"): string | null {
    if (!remote || !this.remoteURL(remote)) return null;
    return this.register(remote, digest);
  }

  namedURL(category: string, name: string, digest: string): string | null {
    if (!categories.has(category) || !namedImage.test(name)) return null;
    const remote = new URL(`/static/raw/${category}/${name}.png`, this.apiBaseUrl).href;
    return this.register(remote, digest);
  }

  file(name: string): Buffer | null {
    if (!imageName.test(name)) return null;
    const path = join(this.root, name);
    return existsSync(path) ? readFileSync(path) : null;
  }

  async fetchFile(name: string): Promise<Buffer | null> {
    const current = this.file(name);
    if (current) return current;
    const source = imageName.test(name) ? this.index[name] ?? this.readIndex()[name] : undefined;
    if (!source) return null;
    const url = this.remoteURL(source.url);
    if (!url) return null;
    const path = join(this.root, name);
    const active = this.pending.get(name) ?? this.download(url, path);
    this.pending.set(name, active);
    try { await active; return this.file(name); }
    finally { this.pending.delete(name); }
  }

  private async ensure(remote: string): Promise<void> {
    const url = this.remoteURL(remote);
    if (!url) return;
    const local = this.register(remote, "upstream");
    if (!local) return;
    const name = local.split("/").at(-1)!, path = join(this.root, name);
    if (existsSync(path)) return;
    const active = this.pending.get(name) ?? this.download(url, path);
    this.pending.set(name, active);
    try { await active; }
    finally { this.pending.delete(name); }
  }

  private async download(url: URL, path: string): Promise<void> {
    const partial = `${path}.part`;
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
      const finalURL = response.url ? this.remoteURL(response.url) : url;
      if (!response.ok || !finalURL) throw new AppError("image_cache_download_failed", `素材下载失败：${response.status}`, 502);
      const tooLarge = () => new AppError("image_cache_too_large", "素材文件过大", 502);
      const data = await readBoundedBody(response, 50 * 1024 * 1024, tooLarge);
      if (!validImage(data)) throw new AppError("image_cache_invalid", "素材文件格式无效", 502);
      writeFileSync(partial, data, { mode: 0o600 }); renameSync(partial, path);
    } finally { rmSync(partial, { force: true }); }
  }

  private imageURLs(value: unknown): string[] {
    if (Array.isArray(value)) return value.flatMap((item) => this.imageURLs(item));
    if (!value || typeof value !== "object") return [];
    return Object.entries(value).flatMap(([key, child]) =>
      imageKeys.has(key) && typeof child === "string" && this.remoteURL(child)
        ? [child] : this.imageURLs(child));
  }

  private remoteURL(value: string): URL | null {
    if (!this.networkEnabled) return null;
    try {
      const url = new URL(value), host = url.hostname.toLowerCase();
      const apiHost = new URL(this.apiBaseUrl).hostname.toLowerCase();
      return url.protocol === "https:" && !url.username && !url.password
        && (host === apiHost || host === "static.snaphutaorp.org"
          || host === "mihoyo.com" || host.endsWith(".mihoyo.com")) ? url : null;
    } catch { return null; }
  }
  private register(remote: string, digest: string): string | null {
    if (!this.remoteURL(remote)) return null;
    const name = this.name(remote, digest);
    if (!this.index[name]) {
      Object.assign(this.index, this.readIndex());
      this.index[name] = { url: remote, digest };
      writeFileSync(this.indexPath, JSON.stringify(this.index), { mode: 0o600 });
    }
    return `/v1/gacha-resources/cache/${name}`;
  }
  private name(remote: string, digest: string): string {
    return `${createHash("sha256").update(`${remote}\0${digest}`).digest("hex")}.img`;
  }
  private readIndex(): CacheIndex {
    try { return JSON.parse(readFileSync(this.indexPath, "utf8")) as CacheIndex; }
    catch { return {}; }
  }
}

function validImage(data: Buffer): boolean {
  if (!data.length || data.length > 50 * 1024 * 1024) return false;
  const hex = data.subarray(0, 12).toString("hex");
  return hex.startsWith("89504e470d0a1a0a") || hex.startsWith("ffd8ff")
    || (hex.startsWith("52494646") && hex.slice(16, 24) === "57454250");
}
