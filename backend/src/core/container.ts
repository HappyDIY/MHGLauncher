import { mkdirSync } from "node:fs";
import { Store } from "./database";
import { settings, type Settings } from "./config";
import type { Provider } from "../providers/provider";
import { FixtureProvider } from "../providers/fixture";
import { LiveProvider } from "../providers/live";
import { AccountService } from "../services/accounts";
import { GameService } from "../services/games";
import { ImageCache } from "../services/images";
import { NoteService } from "../services/notes";
import { WishService } from "../services/wishes";
import { WishTasks } from "../services/wish-tasks";

export class Container {
  readonly settings: Settings;
  readonly store: Store;
  readonly provider: Provider;
  readonly accounts: AccountService;
  readonly games: GameService;
  readonly images: ImageCache;
  readonly notes: NoteService;
  readonly wishes: WishService;
  readonly wishTasks: WishTasks;

  constructor(config = settings()) {
    this.settings = config; mkdirSync(config.dataDir, { recursive: true });
    this.store = new Store(config.databasePath);
    this.provider = config.providerMode === "fixture" ? new FixtureProvider(config.fixtureDir) : new LiveProvider(config);
    this.images = new ImageCache(config.dataDir);
    this.accounts = new AccountService(this.store, this.provider);
    this.games = new GameService(this.store, this.provider, config.dataDir);
    this.notes = new NoteService(this.store, this.provider);
    this.wishes = new WishService(this.store, this.provider, this.images);
    this.wishTasks = new WishTasks(this.accounts, this.wishes);
  }

  close(): void { this.store.close(); }
}

declare global { var mhgContainer: Container | undefined; }
export function container(): Container { return globalThis.mhgContainer ??= new Container(); }
export function closeContainer(): void { globalThis.mhgContainer?.close(); globalThis.mhgContainer = undefined; }
