import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes, randomUUID } from "node:crypto";
import { AppError } from "../core/errors";

interface Saved { profile?: string; device_id?: string; fp_device_id?: string; hoyoplay_device_id?: string; device_name?: string; product_name?: string; device_fp?: string }
const text = (length: number): string => randomBytes(length).toString("base64url").toUpperCase().slice(0, length);
const lowerText = (length: number): string => [...randomBytes(length)].map((value) => "0123456789abcdefghijklmnopqrstuvwxyz"[value % 36]).join("");

export class Device {
  readonly deviceId: string; readonly fpDeviceId: string; readonly hoyoplayDeviceId: string; readonly deviceName: string; readonly productName: string;
  deviceFP: string;
  constructor(private readonly path: string) {
    const value = this.load(); this.deviceId = value.device_id ?? randomUUID(); this.fpDeviceId = value.fp_device_id ?? randomBytes(8).toString("hex");
    this.hoyoplayDeviceId = value.hoyoplay_device_id?.match(/^[0-9a-z]{53}$/) ? value.hoyoplay_device_id : lowerText(53);
    this.deviceName = value.device_name ?? text(12); this.productName = value.product_name ?? text(6);
    this.deviceFP = value.profile === "snap-hutao-android-v2" ? value.device_fp ?? "" : "";
    if (!value.hoyoplay_device_id || !this.deviceFP) this.save();
  }

  get loginDeviceId(): string {
    return this.hoyoplayDeviceId;
  }

  async fingerprint(): Promise<string> {
    if (this.deviceFP) return this.deviceFP;
    const response = await fetch("https://public-data-api.mihoyo.com/device-fp/api/getFp", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(this.payload()) });
    const body = await response.json() as { retcode?: number; data?: { device_fp?: string } };
    if (!response.ok || body.retcode !== 0 || !body.data?.device_fp) throw new AppError("device_fp_failed", "米游社设备注册失败，请稍后重试", 502);
    this.deviceFP = body.data.device_fp; this.save(); return this.deviceFP;
  }

  private payload(): Record<string, string> {
    const ext = { proxyStatus: 0, isRoot: 0, romCapacity: "512", deviceName: this.deviceName, productName: this.productName,
      romRemain: "512", hostname: "dg02-pool03-kvm87", screenSize: "1440x2905", isTablet: 0, aaid: "", model: this.deviceName,
      brand: "XiaoMi", hardware: "qcom", deviceType: "OP5913L1", devId: "REL", serialNumber: "unknown", sdCapacity: 512215,
      buildTime: "1693626947000", buildUser: "android-build", simState: 5, ramRemain: "239814", appUpdateTimeDiff: 1702604034482,
      deviceInfo: `XiaoMi/${this.productName}/OP5913L1:13/SKQ1.221119.001/T.118e6c7-5aa23-73911:user/release-keys`,
      vaid: "", buildType: "user", sdkVersion: "34", ui_mode: "UI_MODE_TYPE_NORMAL", isMockLocation: 0, cpuType: "arm64-v8a",
      isAirMode: 0, ringMode: 2, chargeStatus: 1, manufacturer: "XiaoMi", emulatorStatus: 0, appMemory: "512", osVersion: "14",
      vendor: "unknown", accelerometer: "1.4883357x7.1712894x6.2847486", sdRemain: 239600, buildTags: "release-keys",
      packageName: "com.mihoyo.hyperion", networkType: "WiFi", oaid: "", debugStatus: 1, ramCapacity: "469679",
      magnetometer: "20.081251x-27.487501x2.1937501", display: `${this.productName}_13.1.0.181(CN01)`,
      appInstallTimeDiff: 1688455751496, packageVersion: "2.20.1", gyroscope: "0.030226856x0.014647375x0.010652636",
      batteryStatus: 100, hasKeyboard: 0, board: "taro" };
    return { device_id: this.fpDeviceId, seed_id: randomUUID(), seed_time: String(Date.now()), platform: "2", device_fp: randomBytes(7).toString("hex").slice(0, 13),
      app_name: "bbs_cn", bbs_device_id: this.deviceId, ext_fields: JSON.stringify(ext) };
  }

  private load(): Saved { try { return existsSync(this.path) ? JSON.parse(readFileSync(this.path, "utf8")) as Saved : {}; } catch { return {}; } }
  private save(): void {
    mkdirSync(dirname(this.path), { recursive: true }); const temporary = `${this.path}.tmp`;
    writeFileSync(temporary, JSON.stringify({ profile: "snap-hutao-android-v2", device_id: this.deviceId, fp_device_id: this.fpDeviceId, hoyoplay_device_id: this.hoyoplayDeviceId,
      device_name: this.deviceName, product_name: this.productName, device_fp: this.deviceFP }));
    chmodSync(temporary, 0o600); renameSync(temporary, this.path);
  }
}
