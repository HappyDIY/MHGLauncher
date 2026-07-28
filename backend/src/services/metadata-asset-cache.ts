import type { MetadataRepository } from "./metadata-repository";
import { ImageResourceCache, type ImageResource } from "./image-resource-cache";
import type { SnapAssets } from "./snap-metadata";

const categories: Record<keyof SnapAssets, string> = {
  avatars: "AvatarIcon",
  weapons: "EquipIcon",
  reliquaries: "RelicIcon",
  skills: "Skill",
  talents: "Talent",
};

export class MetadataAssetCache {
  constructor(
    private readonly repository: MetadataRepository,
    private readonly images: ImageResourceCache,
  ) {}

  async preload(): Promise<void> {
    const snapshot = this.repository.snapshot();
    if (!snapshot) return;
    const resources: ImageResource[] = [];
    for (const [kind, category] of Object.entries(categories) as [keyof SnapAssets, string][]) {
      for (const [name, digest] of Object.values(snapshot.assets[kind])) {
        resources.push({ category, name, digest });
      }
    }
    for (const event of snapshot.events) {
      resources.push({ remote: event.banner, digest: snapshot.oid });
    }
    for (const value of [...snapshot.achievements, ...snapshot.goals]) {
      if (value.Icon) resources.push({
        category: "AchievementIcon", name: value.Icon, digest: snapshot.oid,
      });
    }
    await this.images.preload(resources);
  }
}
