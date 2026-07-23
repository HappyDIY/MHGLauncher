export default {
  mutate: [
    "src/api/router.ts:23-42",
    "src/core/errors.ts",
    "src/services/game-launch-process.ts",
    "src/services/game-install-resume.ts",
    "src/services/wish-tasks.ts",
  ],
  testRunner: "vitest",
  concurrency: 1,
  coverageAnalysis: "perTest",
  reporters: ["clear-text", "progress", "html"],
  thresholds: {
    high: 80,
    low: 70,
    break: 70,
  },
  vitest: {
    configFile: "vitest.mutation.config.ts",
  },
};
