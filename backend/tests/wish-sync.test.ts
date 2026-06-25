import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { AppError } from "../src/core/errors";
import { Store } from "../src/core/database";
import type { GameRole, WishRecord } from "../src/core/models";
import { LiveProvider } from "../src/providers/live";
import type { Provider } from "../src/providers/provider";
import { wishSyncLimitedMessage } from "../src/providers/wish-sync";
import type { AccountService } from "../src/services/accounts";
import type { ImageCache } from "../src/services/images";
import { WishTasks } from "../src/services/wish-tasks";
import { WishService } from "../src/services/wishes";

const roots: string[] = [];
const role: GameRole = { uid: "100000001", nickname: "旅行者", region: "cn_gf01", level: 60, selected: true };

function liveProvider(sleep: () => Promise<void>): LiveProvider {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-wish-sync-")); roots.push(dataDir);
  return new LiveProvider({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "", providerMode: "live",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, downloadSpeedLimitKB: 0, socketPath: join(dataDir, "test.sock") }, sleep);
}

function wish(id: string, type: string): WishRecord {
  return { id, uid: role.uid, gacha_type: type, uigf_gacha_type: type, item_id: `item-${id}`, name: `物品${id}`,
    item_type: "角色", rank: 4, time: "2026-01-01T00:00:00" };
}

function remoteWish(id: string, type: string): Record<string, string> {
  return { id, gacha_type: type, item_id: `item-${id}`, name: `物品${id}`, item_type: "角色", rank_type: "4", time: "2026-01-01 00:00:00" };
}

afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("祈愿同步限流", () => {
  test("LiveProvider 按页和卡池等待，限流时停止后续卡池", async () => {
    const sleep = vi.fn(async () => {});
    const provider = liveProvider(sleep);
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("genAuthKey")) return Response.json({ retcode: 0, data: { authkey: "auth-key" } });
      if (url.includes("gacha_type=100") && url.includes("end_id=0")) {
        return Response.json({ retcode: 0, data: { list: Array.from({ length: 20 }, (_, index) => remoteWish(`100-${index + 1}`, "100")) } });
      }
      if (url.includes("gacha_type=100")) return Response.json({ retcode: 0, data: { list: [remoteWish("100-21", "100")] } });
      return Response.json({ retcode: -1, message: "visit too frequently", data: null });
    });

    const iterator = provider.wishes("stoken=fixture", role, {})[Symbol.asyncIterator]();
    const first = await iterator.next();
    expect(first.done).toBe(false);
    expect(first.value).toHaveLength(21);
    await expect(iterator.next()).rejects.toMatchObject({ code: "wish_sync_limited", message: wishSyncLimitedMessage });
    expect(sleep).toHaveBeenCalledTimes(3);
  });

  test("保存层只落库已完整读取的前序卡池", async () => {
    const root = mkdtempSync(join(tmpdir(), "mhg-wish-store-")); roots.push(root);
    const store = new Store(join(root, "test.db"));
    const provider = { async *wishes() {
      yield [wish("complete-1", "100")];
      throw new AppError("wish_sync_limited", wishSyncLimitedMessage, 429);
    } } as unknown as Provider;
    const service = new WishService(store, provider, {} as ImageCache);

    await expect(service.sync("stoken=fixture", role)).rejects.toMatchObject({ code: "wish_sync_limited" });
    expect(store.all("SELECT id,gacha_type FROM wishes WHERE uid=?", role.uid)).toEqual([{ id: "complete-1", gacha_type: "100" }]);
    store.close();
  });

  test("祈愿任务透出限流错误码", async () => {
    const tasks = new WishTasks({ selectedRole: () => role } as AccountService, {
      sync: async () => { throw new AppError("wish_sync_limited", wishSyncLimitedMessage, 429); },
    } as unknown as WishService);
    const job = tasks.startSync("stoken=fixture");
    await waitFor(() => tasks.get(job.id).status === "failed");
    expect(tasks.get(job.id)).toMatchObject({ error_code: "wish_sync_limited", error: wishSyncLimitedMessage });
  });
});

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("等待任务状态超时");
}
