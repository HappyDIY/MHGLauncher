import { describe, expect, test } from "vitest";
import { settings } from "../src/core/config";
import { AppUpdateService } from "../src/services/app-updates";

const release = {
  version: "0.2.0",
  download_url: "https://download.example/MHGLauncher-0.2.0.dmg",
  sha256: "a".repeat(64),
  size: 1024,
  changelog: "新增自动更新检测",
};

describe("应用更新代理", () => {
  test("从云端读取并校验更新信息", async () => {
    const service = new AppUpdateService(settings({ NODE_ENV: "test", MHG_CLOUD_BASE_URL: "https://cloud.example" }), async (input) => {
      expect(String(input)).toBe("https://cloud.example/api/v1/updates/latest");
      return Response.json(release);
    });
    await expect(service.latest()).resolves.toEqual(release);
  });

  test("拒绝降级下载地址和异常响应", async () => {
    const config = settings({ NODE_ENV: "test", MHG_CLOUD_BASE_URL: "https://cloud.example" });
    const insecure = new AppUpdateService(config, async () => Response.json({
      ...release, download_url: "http://download.example/update.dmg",
    }));
    await expect(insecure.latest()).rejects.toMatchObject({ code: "update_payload_invalid" });
    const oversized = new AppUpdateService(config, async () => new Response("{}", {
      headers: { "Content-Length": String(1024 * 1024 + 1) },
    }));
    await expect(oversized.latest()).rejects.toMatchObject({ code: "update_payload_invalid" });
  });

  test("屏蔽云端内部错误码", async () => {
    const service = new AppUpdateService(
      settings({ NODE_ENV: "test", MHG_CLOUD_BASE_URL: "https://cloud.example" }),
      async () => Response.json({ code: "secret", message: "更新未配置" }, { status: 503 }),
    );
    await expect(service.latest()).rejects.toMatchObject({ code: "update_check_failed", message: "更新未配置" });
  });
});
