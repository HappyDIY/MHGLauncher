import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { Store } from "../src/core/database";
import type { DailyNote, GachaEvent } from "../src/core/models";
import type { GachaResourceService } from "../src/services/gacha-resources";
import { NotificationService } from "../src/services/notifications";

const roots: string[] = [];

describe("消息提醒业务", () => {
  afterEach(() => {
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  test("只有客户端确认投递后才抑制重复提醒", () => {
    const context = fixture("2026-07-24T12:00:00Z");
    context.service.update({ daily_commission_enabled: true, daily_commission_time: "20:00" });

    const first = context.service.evaluate(note(), null);
    expect(first).toHaveLength(1);
    expect(context.service.evaluate(note(), null)).toHaveLength(1);
    context.service.acknowledge(first.map(({ key }) => key));
    expect(context.service.evaluate(note(), null)).toHaveLength(0);
    context.close();
  });

  test("委托完成但额外奖励未领取时仍提醒", () => {
    const context = fixture("2026-07-24T12:00:00Z");
    context.service.update({ daily_commission_enabled: true, daily_commission_time: "20:00" });
    expect(context.service.evaluate(note({ finished_tasks: 4 }), null)[0]?.title).toContain("奖励");
    expect(context.service.evaluate(note({ extra_task_reward_received: true }), null)).toHaveLength(0);
    context.close();
  });

  test("北京时间凌晨与上午使用同一自然日去重键", () => {
    const context = fixture("2026-07-23T16:30:00Z");
    context.service.update({ daily_commission_enabled: true, daily_commission_time: "00:00" });
    const events = context.service.evaluate(note(), null);
    context.service.acknowledge(events.map(({ key }) => key));
    context.setNow("2026-07-24T00:30:00Z");
    expect(context.service.evaluate(note(), null)).toHaveLength(0);
    context.close();
  });

  test("体力降低后再次回满会重新提醒", () => {
    const context = fixture("2026-07-24T12:00:00Z");
    context.service.update({ resin_full_enabled: true });
    const full = note({ current_resin: 200 });
    const first = context.service.evaluate(full, null);
    context.service.acknowledge(first.map(({ key }) => key));
    expect(context.service.evaluate(full, null)).toHaveLength(0);
    context.service.evaluate(note({ current_resin: 199 }), null);
    expect(context.service.evaluate(full, null)).toHaveLength(1);
    context.close();
  });

  test("卡池只在北京时间的实际开始时刻后提醒", () => {
    const event = gachaEvent("2026-07-24T06:00:00+08:00");
    const context = fixture("2026-07-23T21:59:00Z", [event]);
    expect(context.service.evaluate(null, null)).toHaveLength(0);
    context.setNow("2026-07-23T22:00:00Z");
    const started = context.service.evaluate(null, null)[0];
    expect(started?.destination).toBe("gachaHistory");
    context.setNow("2026-07-24T22:00:00Z");
    expect(context.service.evaluate(null, null)[0]?.key).toBe(started?.key);
    context.close();
  });
});

function fixture(initial: string, events: GachaEvent[] = []) {
  const root = mkdtempSync(join(tmpdir(), "mhg-notification-")); roots.push(root);
  const store = new Store(join(root, "test.db"));
  let now = new Date(initial);
  const resources = { events: () => events } as unknown as GachaResourceService;
  const service = new NotificationService(store, resources, () => now);
  return {
    service,
    setNow(value: string) { now = new Date(value); },
    close() { store.close(); },
  };
}

function note(overrides: Partial<DailyNote> = {}): DailyNote {
  return {
    uid: "100000001", current_resin: 120, max_resin: 200,
    finished_tasks: 4, total_tasks: 4, extra_task_reward_received: false,
    expeditions_finished: 0, expeditions_total: 5, current_home_coin: 0, max_home_coin: 2400,
    weekly_boss_remaining: 3, transformer_ready: false, refreshed_at: "2026-07-24T12:00:00Z",
    ...overrides,
  };
}

function gachaEvent(startedAt: string): GachaEvent {
  return {
    id: "event", version: "6.0", gacha_type: "301", name: "测试卡池",
    started_at: startedAt, ended_at: "2026-08-01T18:00:00+08:00",
    orange_up: [], purple_up: [], updated_at: startedAt,
  };
}
