import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { activate } from "./installer";
import { discoverMirrors, remoteOID, shallowClone } from "./metadata-remote";
import { readSnapMetadata, type MetadataSnapshot } from "./snap-metadata";
import { validateMetadataRepository } from "./metadata-validation";

type ResourceState = "missing" | "syncing" | "ready" | "retry";
export interface ResourceStatus {
  state: ResourceState; oid: string | null; last_checked_at: string | null; last_success_at: string | null;
  trigger_game_version: string | null; using_legacy_cache: boolean; error: string | null;
}
export interface MetadataRepositoryOptions {
  dataDir: string; apiBaseUrl: string; fixtureDir?: string;
  discover?: typeof discoverMirrors; oid?: typeof remoteOID;
  clone?: (url: string, dir: string) => Promise<string | void>;
}

export class MetadataRepository {
  private readonly root: string;
  private readonly destination: string;
  private snapshotCache?: MetadataSnapshot;
  private task?: Promise<ResourceStatus>;
  private current: ResourceStatus;

  constructor(private readonly options: MetadataRepositoryOptions) {
    this.root = join(options.dataDir, "resources");
    this.destination = options.fixtureDir ?? join(this.root, "Snap.Metadata");
    mkdirSync(this.root, { recursive: true, mode: 0o700 });
    for (const name of readdirSync(this.root)) {
      if (/^Snap\.Metadata\.mhg-staging-[a-f0-9-]+$/.test(name)) {
        rmSync(join(this.root, name), { recursive: true, force: true });
      }
    }
    this.current = this.readStatus();
    this.loadSnapshot();
  }

  status(): ResourceStatus { return { ...this.current, state: this.task ? "syncing" : this.current.state }; }
  snapshot(): MetadataSnapshot | undefined { return this.snapshotCache; }

  async ensure(): Promise<MetadataSnapshot | undefined> {
    if (!this.snapshotCache && !this.options.fixtureDir) await this.sync(false);
    return this.snapshotCache;
  }

  sync(force = false, gameVersion?: string): Promise<ResourceStatus> {
    if (this.options.fixtureDir) return Promise.resolve(this.status());
    if (this.task) return this.task;
    this.task = this.performSync(force, gameVersion).finally(() => { this.task = undefined; });
    return this.task;
  }

  trigger(gameVersion?: string): void { void this.sync(false, gameVersion); }

  private async performSync(force: boolean, gameVersion?: string): Promise<ResourceStatus> {
    this.current = { ...this.current, state: "syncing", last_checked_at: new Date().toISOString(), trigger_game_version: gameVersion ?? null, error: null };
    this.persistStatus();
    const failures: string[] = [];
    try {
      const mirrors = await (this.options.discover ?? discoverMirrors)(this.options.apiBaseUrl);
      for (const mirror of mirrors) {
        const staging = join(this.root, `Snap.Metadata.mhg-staging-${randomUUID()}`);
        try {
          const oid = await (this.options.oid ?? remoteOID)(mirror);
          if (!force && this.current.oid === oid && this.snapshotCache) return this.success(oid, gameVersion);
          const clonedOID = await (this.options.clone ?? shallowClone)(mirror, staging);
          const activeOID = clonedOID ?? oid;
          await validateMetadataRepository(staging);
          const snapshot = readSnapMetadata(staging, activeOID);
          rmSync(join(staging, ".git"), { recursive: true, force: true });
          writeFileSync(join(staging, ".mhg-resource.json"), JSON.stringify({ oid: activeOID, activated_at: snapshot.activatedAt }), { mode: 0o600 });
          activate(staging, this.destination); this.snapshotCache = snapshot;
          return this.success(activeOID, gameVersion);
        } catch (error) { failures.push(safeMessage(error)); }
        finally { rmSync(staging, { recursive: true, force: true }); }
      }
      throw new Error(failures.at(-1) ?? "没有可用的 HTTPS 资料镜像");
    } catch (error) {
      this.current = { ...this.current, state: this.snapshotCache ? "retry" : "missing", error: safeMessage(error) };
      this.persistStatus(); return { ...this.current };
    }
  }

  private success(oid: string, gameVersion?: string): ResourceStatus {
    const now = new Date().toISOString();
    this.current = { state: "ready", oid, last_checked_at: now, last_success_at: now,
      trigger_game_version: gameVersion ?? this.current.trigger_game_version, using_legacy_cache: false, error: null };
    this.persistStatus(); return { ...this.current };
  }

  private loadSnapshot(): void {
    if (this.options.fixtureDir) {
      this.snapshotCache = fixtureSnapshot(this.options.fixtureDir);
      this.current = { state: "ready", oid: "fixture", last_checked_at: null, last_success_at: null,
        trigger_game_version: null, using_legacy_cache: false, error: null };
      return;
    }
    try {
      const descriptor = JSON.parse(readFileSync(join(this.destination, ".mhg-resource.json"), "utf8")) as { oid: string };
      this.snapshotCache = readSnapMetadata(this.destination, descriptor.oid);
      this.current = { ...this.current, state: "ready", oid: descriptor.oid, using_legacy_cache: false };
    } catch { /* 首次启动允许继续使用旧资源。 */ }
  }

  private readStatus(): ResourceStatus {
    try { return JSON.parse(readFileSync(join(this.root, "Snap.Metadata.status.json"), "utf8")) as ResourceStatus; }
    catch { return { state: "missing", oid: null, last_checked_at: null, last_success_at: null,
      trigger_game_version: null, using_legacy_cache: existsSync(join(this.root, "gacha-history")), error: null }; }
  }
  private persistStatus(): void {
    writeFileSync(join(this.root, "Snap.Metadata.status.json"), JSON.stringify(this.current), { mode: 0o600 });
  }
}

function fixtureSnapshot(root: string): MetadataSnapshot {
  const items = JSON.parse(readFileSync(join(root, "gacha_items.json"), "utf8")) as Record<string, [string, string, number, string?]>;
  const events = JSON.parse(readFileSync(join(root, "gacha_events.json"), "utf8")) as Record<string, unknown>[];
  return {
    oid: "fixture", activatedAt: new Date(0).toISOString(), assets: { avatars: {}, weapons: {}, reliquaries: {}, skills: {}, talents: {} },
    items: Object.fromEntries(Object.entries(items).map(([id, value]) => [id, { name: value[0], kind: value[1] as "角色" | "武器", rank: value[2], icon: value[3] ?? "", digest: "fixture" }])),
    events: events.map((value) => ({ name: String(value.Name), version: String(value.Version), order: Number(value.Order),
      banner: String(value.Banner), from: String(value.From), to: String(value.To), type: Number(value.Type),
      orange: value.UpOrangeList as number[], purple: value.UpPurpleList as number[] })),
    achievements: JSON.parse(readFileSync(join(root, "achievement.json"), "utf8")),
    goals: JSON.parse(readFileSync(join(root, "achievement_goals.json"), "utf8")),
  };
}
function safeMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/https?:\/\/\S+/g, "[远端地址]").slice(0, 300) || "资料同步失败";
}
