import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { AchievementMetadataBundle } from "./achievement-metadata";
import { parseAchievementMetadata } from "./achievement-metadata";
import { ImageResourceCache } from "./image-resource-cache";
import type { MetadataRepository } from "./metadata-repository";

const iconName = /^[A-Za-z0-9_]{1,128}$/;

export class AchievementResources {
  private readonly imageCache: ImageResourceCache;
  private readonly legacyRoot: string;

  constructor(
    dataDir: string,
    private readonly repository: MetadataRepository,
    apiBaseUrl: string,
    networkEnabled = true,
  ) {
    this.legacyRoot = join(dataDir, "resources", "achievements");
    this.imageCache = new ImageResourceCache(dataDir, apiBaseUrl, networkEnabled);
  }

  async metadata(): Promise<AchievementMetadataBundle> {
    const snapshot = await this.repository.ensure();
    if (snapshot) return { achievements: snapshot.achievements, goals: snapshot.goals };
    const legacy = this.legacyMetadata();
    if (legacy) return legacy;
    throw new AppError("achievement_resources_unavailable", "暂无可用成就资料，请刷新后重试", 503);
  }

  iconUrl(name?: string): string | null {
    const snapshot = this.repository.snapshot();
    return name && iconName.test(name)
      ? this.imageCache.namedURL("AchievementIcon", name, snapshot?.oid ?? "legacy")
      : null;
  }

  async icon(name: string): Promise<Buffer> {
    if (!iconName.test(name)) throw new AppError("achievement_icon_invalid", "成就插图名称无效", 422);
    const local = this.iconUrl(name);
    const fileName = local?.split("/").at(-1);
    const data = fileName ? await this.imageCache.fetchFile(fileName) : null;
    if (!data) throw new AppError("achievement_icon_unavailable", "成就插图暂不可用", 503);
    return data;
  }

  private legacyMetadata(): AchievementMetadataBundle | null {
    const achievement = join(this.legacyRoot, "Achievement.json");
    const goals = join(this.legacyRoot, "AchievementGoal.json");
    if (!existsSync(achievement) || !existsSync(goals)) return null;
    try {
      return {
        achievements: parseAchievementMetadata(readFileSync(achievement, "utf8"), "achievements"),
        goals: parseAchievementMetadata(readFileSync(goals, "utf8"), "goals"),
      };
    } catch { return null; }
  }
}
