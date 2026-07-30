import { expect, test, vi } from "vitest";
import { fixture, request } from "./helpers";

test("Wine 工具端点校验并转发高级命令", async () => {
  const app = fixture();
  const start = vi.spyOn(app.wineTools, "start").mockResolvedValue();
  const response = await request("POST", "/v1/game/wine-tools", {
    action: "run", command: "regedit", performance_profile: "compatibility",
  });
  expect(response.status).toBe(202);
  expect(start).toHaveBeenCalledWith({
    action: "run", command: "regedit", performance_profile: "compatibility",
  });
});

test("Wine 工具端点拒绝包含空字符的命令", async () => {
  const app = fixture();
  const start = vi.spyOn(app.wineTools, "start").mockResolvedValue();
  const response = await request("POST", "/v1/game/wine-tools", {
    action: "run", command: "cmd\0.exe", performance_profile: "optimized",
  });
  expect(response.status).toBe(422);
  expect(start).not.toHaveBeenCalled();
});
