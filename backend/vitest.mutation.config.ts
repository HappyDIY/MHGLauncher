import { configDefaults, defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    pool: "forks",
    include: [
      "tests/game-install-resume.test.ts",
      "tests/game-launch-process.test.ts",
      "tests/game-launch-run.test.ts",
      "tests/game-launch.test.ts",
      "tests/router-injection.test.ts",
      "tests/wish-tasks-mutation.test.ts",
    ],
    exclude: [...configDefaults.exclude, "performance/**"],
  },
});
