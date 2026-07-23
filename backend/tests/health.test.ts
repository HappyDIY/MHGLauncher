import { beforeEach, expect, test } from "vitest";
import { dispatch } from "../src/api/router";
import { fixture } from "./helpers";

beforeEach(() => fixture());

test("健康检查同样要求每次启动令牌", async () => {
  expect((await dispatch(new Request("http://local/health"))).status).toBe(401);
  const response = await dispatch(new Request("http://local/health", {
    headers: { Authorization: "Bearer test-token" },
  }));
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ status: "ok", version: "1.0.0" });
});
