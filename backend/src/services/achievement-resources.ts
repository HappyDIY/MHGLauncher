import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import {
  parseAchievementMetadata,
  type AchievementMetadataBundle,
  type AchievementMetadata,
  type AchievementGoalMetadata,
} from "./achievement-metadata";

const MAX_METADATA_BYTES = 8 * 1024 * 1024;
const MAX_ICON_BYTES = 2 * 1024 * 1024;
const iconName = /^[A-Za-z0-9_]{1,128}$/;
const pngMagic = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

export interface AchievementResourceOptions {
  metadataBaseUrl: string;
  iconBaseUrl: string;
  localMetadataDir?: string;
  fetcher?: Fetcher;
}

export class AchievementResources {
  private readonly root: string;
  private readonly iconRoot: string;
  private readonly fetcher: Fetcher;
  private metadataTask?: Promise<AchievementMetadataBundle>;
  private readonly iconTasks = new Map<string, Promise<Buffer>>();

  constructor(dataDir: string, private readonly options: AchievementResourceOptions) {
    this.root = join(dataDir, "resources", "achievements");
    this.iconRoot = join(this.root, "icons");
    this.fetcher = options.fetcher ?? fetch;
    mkdirSync(this.iconRoot, { recursive: true, mode: 0o700 });
  }

  metadata(): Promise<AchievementMetadataBundle> {
    const task = this.metadataTask ?? this.loadMetadata();
    this.metadataTask = task;
    return task.catch((error) => { this.metadataTask = undefined; throw error; });
  }

  iconUrl(name?: string): string | null {
    return name && iconName.test(name)
      ? `/v1/achievements/resources/icons/${encodeURIComponent(name)}.png`
      : null;
  }

  icon(name: string): Promise<Buffer> {
    if (!iconName.test(name)) return Promise.reject(new AppError("achievement_icon_invalid", "成就插图名称无效", 422));
    const path = join(this.iconRoot, `${name}.png`);
    if (existsSync(path)) return Promise.resolve(readFileSync(path));
    const task = this.iconTasks.get(name) ?? this.downloadIcon(name, path);
    this.iconTasks.set(name, task);
    return task.finally(() => this.iconTasks.delete(name));
  }

  private async loadMetadata(): Promise<AchievementMetadataBundle> {
    if (this.options.localMetadataDir) return this.readLocalMetadata(this.options.localMetadataDir);
    const [achievements, goals] = await Promise.all([
      this.downloadMetadata("Achievement.json", "achievements"),
      this.downloadMetadata("AchievementGoal.json", "goals"),
    ]);
    return { achievements, goals };
  }

  private readLocalMetadata(directory: string): AchievementMetadataBundle {
    return {
      achievements: parseAchievementMetadata(readFileSync(join(directory, "achievement.json"), "utf8"), "achievements"),
      goals: parseAchievementMetadata(readFileSync(join(directory, "achievement_goals.json"), "utf8"), "goals"),
    };
  }

  private downloadMetadata(name: string, kind: "achievements"): Promise<AchievementMetadata[]>;
  private downloadMetadata(name: string, kind: "goals"): Promise<AchievementGoalMetadata[]>;
  private async downloadMetadata(name: string, kind: "achievements" | "goals") {
    const path = join(this.root, name), etagPath = `${path}.etag`;
    const headers: Record<string, string> = {};
    if (existsSync(path) && existsSync(etagPath)) headers["If-None-Match"] = readFileSync(etagPath, "utf8");
    try {
      const response = await this.fetcher(new URL(name, withSlash(this.options.metadataBaseUrl)).href, { headers });
      if (response.status === 304 && existsSync(path)) return parseAchievementMetadata(readFileSync(path, "utf8"), kind);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await bounded(response, MAX_METADATA_BYTES);
      const parsed = parseAchievementMetadata(data.toString("utf8"), kind);
      atomicWrite(path, data);
      const etag = response.headers.get("etag");
      if (etag) atomicWrite(etagPath, Buffer.from(etag)); else rmSync(etagPath, { force: true });
      return parsed;
    } catch (error) {
      if (existsSync(path)) {
        try { return parseAchievementMetadata(readFileSync(path, "utf8"), kind); } catch { /* 继续报告下载错误。 */ }
      }
      throw new AppError("achievement_resources_unavailable", "成就条目下载失败，请检查网络后重试", 503, { cause: String(error) });
    }
  }

  private async downloadIcon(name: string, path: string): Promise<Buffer> {
    try {
      const response = await this.fetcher(new URL(`${name}.png`, withSlash(this.options.iconBaseUrl)).href);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await bounded(response, MAX_ICON_BYTES);
      if (data.length < pngMagic.length || !data.subarray(0, pngMagic.length).equals(pngMagic)) throw new Error("invalid png");
      atomicWrite(path, data);
      return data;
    } catch (error) {
      throw new AppError("achievement_icon_unavailable", "成就插图下载失败", 502, { cause: String(error) });
    }
  }
}

async function bounded(response: Response, limit: number): Promise<Buffer> {
  const declared = Number(response.headers.get("content-length") ?? 0);
  if (declared > limit) throw new Error("resource too large");
  if (!response.body) throw new Error("empty resource");
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return Buffer.concat(chunks, total);
    total += value.length;
    if (total > limit) { await reader.cancel(); throw new Error("resource too large"); }
    chunks.push(value);
  }
}

function atomicWrite(path: string, data: Buffer): void {
  const partial = `${path}.${process.pid}.part`;
  try { writeFileSync(partial, data, { mode: 0o600 }); renameSync(partial, path); }
  finally { rmSync(partial, { force: true }); }
}

function withSlash(value: string): string { return value.endsWith("/") ? value : `${value}/`; }
