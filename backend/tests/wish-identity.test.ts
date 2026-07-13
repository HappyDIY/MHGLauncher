import { expect, test } from "vitest";
import { fixture } from "./helpers";

const record = (uid: string) => ({
  id: "100", uid, gacha_type: "301", uigf_gacha_type: "301", item_id: "1",
  name: uid, item_type: "角色", rank: 5, time: "2026-01-01T00:00:00+08:00",
});

test("祈愿主键按 UID 隔离", () => {
  const app = fixture();
  app.wishes.save([record("100000001"), record("100000002")]);
  expect(app.wishes.list("100000001")[0]?.name).toBe("100000001");
  expect(app.wishes.list("100000002")[0]?.name).toBe("100000002");
});

test("数字 ID 按长度和字典序确定增量顺序", () => {
  const app = fixture();
  app.wishes.save([{ ...record("100000001"), id: "9" }, { ...record("100000001"), id: "10" }]);
  expect(app.wishes.list("100000001").map(({ id }) => id)).toEqual(["10", "9"]);
});
