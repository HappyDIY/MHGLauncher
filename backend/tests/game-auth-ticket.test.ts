import { expect, test, vi } from "vitest";
import type { GameLaunch } from "../src/core/models";
import { fixture, request } from "./helpers";

test("米游社账号启动时换取登录票据且不透传 Cookie", async () => {
  const app = fixture();
  const credential = "stuid=10001; stoken=fixture; mid=fixture-mid";
  const prepared = await (await request("POST", "/v1/auth/cookie-login", { credential })).json();
  await request("POST", "/v1/auth/commit", { transaction_id: prepared.transaction_id });
  const now = new Date().toISOString();
  const launch: GameLaunch = {
    id: "launch-1", status: "preparing", message: "", performance_profile: "optimized",
    metal_hud: false, network_debug: false, wine_log: false, progress: 0.05,
    logs: [], started_at: now, updated_at: now,
  };
  const start = vi.spyOn(app.launches, "start").mockReturnValue(launch);

  const response = await request("POST", "/v1/game/launch", {
    install_path: "/games/Genshin Impact Game", credential,
  });

  expect(response.status).toBe(202);
  expect(start).toHaveBeenCalledWith(expect.objectContaining({
    auth_ticket: "fixture-auth-ticket",
  }));
  expect(start.mock.calls[0]?.[0]).not.toHaveProperty("credential");
  expect(start.mock.calls[0]?.[0]).not.toHaveProperty("account");
});
