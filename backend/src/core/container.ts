import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { Store } from "./database";
import { settings, type Settings } from "./config";
import type { Provider } from "../providers/provider";
import { FixtureProvider } from "../providers/fixture";
import { LiveProvider } from "../providers/live";
import { FixtureGameRecordSource } from "../providers/fixture-game-record";
import { LiveGameRecordSource } from "../providers/live-game-record";
import { AccountService } from "../services/accounts";
import { CharacterService } from "../services/characters";
import { GameService } from "../services/games";
import { GameLaunchService } from "../services/game-launches";
import { ImageCache } from "../services/images";
import { NoteService } from "../services/notes";
import { WishService } from "../services/wishes";
import { WishTasks } from "../services/wish-tasks";

export class Container {
  readonly settings: Settings;
  readonly store: Store;
  readonly provider: Provider;
  readonly characters: CharacterService;
  readonly accounts: AccountService;
  readonly games: GameService;
  readonly launches: GameLaunchService;
  readonly images: ImageCache;
  readonly notes: NoteService;
  readonly wishes: WishService;
  readonly wishTasks: WishTasks;

  constructor(config = settings()) {
    this.settings = config; mkdirSync(config.dataDir, { recursive: true });
    this.store = new Store(config.databasePath);
    this.provider = config.providerMode === "fixture" ? new FixtureProvider(config.fixtureDir) : new LiveProvider(config);
    const records = config.providerMode === "fixture" ? new FixtureGameRecordSource() : new LiveGameRecordSource(config);
    this.images = new ImageCache(config.dataDir);
    this.accounts = new AccountService(this.store, this.provider);
    this.characters = new CharacterService(this.store, records);
    this.games = new GameService(this.store, this.provider, config.dataDir, config.downloadWorkers, config.downloadSpeedLimitKB);
    this.launches = new GameLaunchService(
      config.dataDir, process.env.MHG_RUNTIME_ROOT ?? join(process.cwd(), "runtime"), undefined, undefined,
      () => this.games.busy(),
    );
    this.notes = new NoteService(this.store, this.provider);
    this.wishes = new WishService(this.store, this.provider, this.images);
    this.wishTasks = new WishTasks(this.accounts, this.wishes);
  }

  close(): void { this.store.close(); }
}

declare global { var mhgContainer: Container | undefined; }
export function container(): Container { return globalThis.mhgContainer ??= new Container(); }
export function closeContainer(): void { globalThis.mhgContainer?.close(); globalThis.mhgContainer = undefined; }
