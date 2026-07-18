import { expect, test } from "@playwright/test";

test("登录页在不同视口保持可用", async ({ page }, testInfo) => {
  await page.emulateMedia({ colorScheme: testInfo.project.name === "mobile" ? "dark" : "light", reducedMotion: "reduce" });
  await page.goto("/login");
  await expect(page.getByRole("heading", { name: "云端管理面板" })).toBeVisible();
  await expect(page.getByLabel("邮箱")).toBeVisible();
  await expect(page.getByLabel("密码")).toBeVisible();
  await expect(page.getByRole("button", { name: "登录" })).toBeVisible();
  await expect(page.locator("main")).toHaveScreenshot(`login-${testInfo.project.name}.png`, { animations: "disabled", maxDiffPixels: 50 });
});
