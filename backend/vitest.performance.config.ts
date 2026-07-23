import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["performance/**/*.test.ts"],
    testTimeout: 30_000,
  },
});
