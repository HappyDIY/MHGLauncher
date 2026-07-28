import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { Store } from "./database";
import { settings, type Settings } from "./config";
import type { Provider } from "../providers/provider";
import { FixtureProvider } from "../providers/fixture";
import { LiveProvider } from "../providers/live";
import { AccountService } from "../services/accounts";
import { GameService } from "../services/games";
import { GameLaunchService } from "../services/game-launches";
import { NoteService } from "../services/notes";
import { WishService } from "../services/wishes";
import { WishTasks } from "../services/wish-tasks";
import type { GameRecordSource } from "../providers/game-record";
import { FixtureGameRecordSource } from "../providers/fixture-game-record";
import { LiveGameRecordSource } from "../providers/live-game-record";
import { CharacterService } from "../services/characters";
import { AchievementService } from "../services/achievements";
import { NotificationService } from "../services/notifications";
import { GachaEventService } from "../services/gacha-events";
import { CloudSyncService } from "../services/cloud-sync";
import { PreparedLoginStore } from "../services/prepared-logins";
import { ResourceCoordinator } from "../services/resource-coordinator";
import { GachaResourceService } from "../services/gacha-resources";
import { AchievementResources } from "../services/achievement-resources";
import { AppUpdateService } from "../services/app-updates";
import { MetadataRepository, type ResourceStatus } from "../services/metadata-repository";
import { ImageResourceCache } from "../services/image-resource-cache";
import { MetadataAssetCache, type MetadataAssetStatus } from "../services/metadata-asset-cache";

export class Container {
  readonly settings: Settings;
  readonly store: Store;
  readonly provider: Provider;
  readonly accounts: AccountService;
  readonly games: GameService;
  readonly launches: GameLaunchService;
  readonly gachaResources: GachaResourceService;
  readonly metadataRepository: MetadataRepository;
  private readonly metadataAssets: MetadataAssetCache;
  readonly notes: NoteService;
  readonly wishes: WishService;
	  readonly wishTasks: WishTasks;
	  readonly records: GameRecordSource;
	  readonly characters: CharacterService;
	  readonly achievements: AchievementService;
	  readonly achievementResources: AchievementResources;
	  readonly notifications: NotificationService;
	  readonly gachaEvents: GachaEventService;
	  readonly cloud: CloudSyncService;
	  readonly preparedLogins: PreparedLoginStore;
	  readonly appUpdates: AppUpdateService;

  constructor(config = settings()) {
    this.settings = config; mkdirSync(config.dataDir, { recursive: true });
    const hutaoApiBaseUrl = config.hutaoApiBaseUrl ?? "https://api.snaphutaorp.org";
    this.store = new Store(config.databasePath);
	    this.provider = config.providerMode === "fixture" ? new FixtureProvider(config.fixtureDir) : new LiveProvider(config);
	    this.records = config.providerMode === "fixture" ? new FixtureGameRecordSource(config.fixtureDir) : new LiveGameRecordSource(config);
    const fixtureMetadata = config.providerMode === "fixture"
      ? join(config.fixtureDir, "..", "src", "mhglauncher", "data") : undefined;
    this.metadataRepository = new MetadataRepository({
      dataDir: config.dataDir, apiBaseUrl: hutaoApiBaseUrl, fixtureDir: fixtureMetadata,
    });
    const networkEnabled = config.providerMode !== "fixture";
    const imageCache = new ImageResourceCache(config.dataDir, hutaoApiBaseUrl, networkEnabled);
    this.metadataAssets = new MetadataAssetCache(config.dataDir, this.metadataRepository, imageCache);
    this.gachaResources = new GachaResourceService(
      config.dataDir, this.metadataRepository, hutaoApiBaseUrl, networkEnabled, imageCache,
    );
	this.achievementResources = new AchievementResources(
	  config.dataDir, this.metadataRepository, hutaoApiBaseUrl, networkEnabled, imageCache,
	);
    this.accounts = new AccountService(this.store, this.provider);
    this.preparedLogins = new PreparedLoginStore();
    const resources = new ResourceCoordinator();
    this.games = new GameService(
      this.store, this.provider, config.dataDir, config.downloadWorkers, config.downloadSpeedLimitKB,
      resources, (version) => { void this.syncMetadata(false, version); },
    );
    this.launches = new GameLaunchService(
      config.dataDir, process.env.MHG_RUNTIME_ROOT ?? join(process.cwd(), "runtime"), undefined, undefined, resources,
    );
    this.notes = new NoteService(this.store, this.provider);
	    this.wishes = new WishService(this.store, this.provider, this.gachaResources, this.records);
	    this.wishTasks = new WishTasks(this.accounts, this.wishes);
	    this.characters = new CharacterService(this.store, this.records, this.gachaResources);
	    this.achievements = new AchievementService(this.store, this.achievementResources);
	    this.gachaEvents = new GachaEventService(this.gachaResources);
	    this.notifications = new NotificationService(this.store, this.gachaResources);
	    this.cloud = new CloudSyncService(config, this.store, this.provider, this.wishes, this.achievements);
	    this.appUpdates = new AppUpdateService(config);
	  }

  async syncMetadata(force = false, gameVersion?: string): Promise<ResourceStatus> {
    const status = await this.metadataRepository.sync(force, gameVersion);
    await this.metadataAssets.preload();
    return status;
  }

  resourceStatus(): ResourceStatus & MetadataAssetStatus {
    return { ...this.metadataRepository.status(), ...this.metadataAssets.status() };
  }

  close(): void { this.launches.close(); this.store.close(); }
}

declare global { var mhgContainer: Container | undefined; }
export function container(): Container { return globalThis.mhgContainer ??= new Container(); }
export function closeContainer(): void { globalThis.mhgContainer?.close(); globalThis.mhgContainer = undefined; }
