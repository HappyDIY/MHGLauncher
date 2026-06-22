import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export class ImageCache {
  private readonly urls = new Map<string, string>();
  private readonly pending = new Map<string, Promise<string | null>>();
  readonly root: string;

  constructor(dataDir: string) {
    this.root = join(dataDir, "cache", "images");
    mkdirSync(this.root, { recursive: true });
  }

  localURL(remote: string): string {
    if (!remote) return "";
    const name = `${createHash("sha1").update(remote).digest("hex")}.png`;
    this.urls.set(name, remote);
    return `/v1/images/gacha/${name}`;
  }

  async get(name: string): Promise<Buffer | null> {
    if (!/^[a-f0-9]{40}\.png$/.test(name)) return null;
    const path = join(this.root, name);
    if (existsSync(path)) return readFileSync(path);
    const remote = this.urls.get(name);
    if (!remote) return null;
    const active = this.pending.get(name) ?? this.download(remote, path);
    this.pending.set(name, active);
    try { return await active ? readFileSync(path) : null; }
    finally { this.pending.delete(name); }
  }

  async ensure(remote: string): Promise<void> {
    const endpoint = this.localURL(remote);
    await this.get(endpoint.split("/").at(-1) ?? "");
  }

  private async download(remote: string, path: string): Promise<string | null> {
    const partial = `${path}.part`;
    try {
      const response = await fetch(remote, { signal: AbortSignal.timeout(30_000) });
      if (!response.ok) throw new Error(`图片下载失败：${response.status}`);
      writeFileSync(partial, Buffer.from(await response.arrayBuffer()));
      renameSync(partial, path);
      return path;
    } catch (error) {
      rmSync(partial, { force: true });
      throw error;
    }
  }
}
