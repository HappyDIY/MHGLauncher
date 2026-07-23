import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { GameCharacter } from "../core/models";
import { AppError } from "../core/errors";
import { readBoundedBody } from "./http-response";

const imageName = /^[a-f0-9]{64}\.img$/;
const imageKeys = new Set(["icon", "image", "side_icon"]);

export class ImageResourceCache {
  private readonly root: string;
  private readonly pending = new Map<string, Promise<void>>();

  constructor(dataDir: string) {
    this.root = join(dataDir, "resources", "image-cache");
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
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

  localURL(remote: string | null | undefined): string | null {
    if (!remote || !this.remoteURL(remote)) return null;
    const name = this.name(remote);
    return existsSync(join(this.root, name)) ? `/v1/gacha-resources/cache/${name}` : null;
  }

  file(name: string): Buffer | null {
    if (!imageName.test(name)) return null;
    const path = join(this.root, name);
    return existsSync(path) ? readFileSync(path) : null;
  }

  private async ensure(remote: string): Promise<void> {
    const url = this.remoteURL(remote);
    if (!url) return;
    const name = this.name(remote), path = join(this.root, name);
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
    try {
      const url = new URL(value), host = url.hostname.toLowerCase();
      return url.protocol === "https:" && !url.username && !url.password
        && (host === "mihoyo.com" || host.endsWith(".mihoyo.com")) ? url : null;
    } catch { return null; }
  }
  private name(remote: string): string { return `${createHash("sha256").update(remote).digest("hex")}.img`; }
}

function validImage(data: Buffer): boolean {
  if (!data.length || data.length > 50 * 1024 * 1024) return false;
  const hex = data.subarray(0, 12).toString("hex");
  return hex.startsWith("89504e470d0a1a0a") || hex.startsWith("ffd8ff")
    || (hex.startsWith("52494646") && hex.slice(16, 24) === "57454250");
}
