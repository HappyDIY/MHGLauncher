import { describe, expect, test } from "vitest";
import { equalToken } from "../src/auth";

describe("云端认证工具", () => {
  test("令牌比较保持稳定", () => {
    expect(equalToken("abc", "abc")).toBe(true);
    expect(equalToken("abc", "abd")).toBe(false);
    expect(equalToken("abc", "abcd")).toBe(false);
  });
});
