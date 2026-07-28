import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
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
export interface MetadataAssetStatus {
  asset_state: "missing" | "syncing" | "ready" | "retry";
  asset_completed: number; asset_total: number; asset_failed: number;
  initial_install_required: boolean;
}

export class MetadataAssetCache {
  private readonly marker: string;
  private current: MetadataAssetStatus;

  constructor(
    dataDir: string,
    private readonly repository: MetadataRepository,
    private readonly images: ImageResourceCache,
  ) {
    const root = join(dataDir, "resources", "image-cache");
    mkdirSync(root, { recursive: true, mode: 0o700 });
    this.marker = join(root, ".metadata-assets-ready.json");
    const required = !existsSync(this.marker);
    this.current = {
      asset_state: required ? "missing" : "ready", asset_completed: 0,
      asset_total: 0, asset_failed: 0, initial_install_required: required,
    };
  }

  status(): MetadataAssetStatus { return { ...this.current }; }

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
    this.current = { ...this.current, asset_state: "syncing", asset_failed: 0 };
    const result = await this.images.preload(resources, (progress) => {
      this.current = { ...this.current, asset_state: "syncing",
        asset_completed: progress.completed, asset_total: progress.total,
        asset_failed: progress.failed };
    });
    writeFileSync(this.marker, JSON.stringify({
      oid: snapshot.oid, completed_at: new Date().toISOString(), failed: result.failed,
    }), { mode: 0o600 });
    this.current = { asset_state: result.failed ? "retry" : "ready",
      asset_completed: result.completed, asset_total: result.total, asset_failed: result.failed,
      initial_install_required: false };
  }
}
