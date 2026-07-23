import { configDefaults, defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    exclude: [...configDefaults.exclude, "performance/**", ".stryker-tmp/**", "reports/**"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      reporter: ["text", "json", "json-summary", "lcov"],
      thresholds: {
        statements: 78,
        branches: 70,
        functions: 83,
        lines: 85,
      },
    },
  },
});
