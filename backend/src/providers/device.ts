import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes, randomUUID } from "node:crypto";
import { AppError } from "../core/errors";

interface Saved { profile?: string; device_id?: string; fp_device_id?: string; device_name?: string; product_name?: string; device_fp?: string }
const text = (length: number): string => randomBytes(length).toString("base64url").toUpperCase().slice(0, length);

export class Device {
  readonly deviceId: string; readonly fpDeviceId: string; readonly deviceName: string; readonly productName: string;
  deviceFP: string;
  constructor(private readonly path: string) {
    const value = this.load(); this.deviceId = value.device_id ?? randomUUID(); this.fpDeviceId = value.fp_device_id ?? randomBytes(8).toString("hex");
    this.deviceName = value.device_name ?? text(12); this.productName = value.product_name ?? text(6);
    this.deviceFP = value.profile === "android-v1" ? value.device_fp ?? "" : ""; if (!this.deviceFP) this.save();
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
      manufacturer: "XiaoMi", screenSize: "1440x2905", osVersion: "14", packageName: "com.mihoyo.hyperion", networkType: "WiFi",
      model: this.deviceName, brand: "XiaoMi", hardware: "qcom", deviceType: "OP5913L1", sdkVersion: "34", board: "taro" };
    return { device_id: this.fpDeviceId, seed_id: randomUUID(), seed_time: String(Date.now()), platform: "2", device_fp: randomBytes(7).toString("hex").slice(0, 13),
      app_name: "bbs_cn", bbs_device_id: this.deviceId, ext_fields: JSON.stringify(ext) };
  }

  private load(): Saved { try { return existsSync(this.path) ? JSON.parse(readFileSync(this.path, "utf8")) as Saved : {}; } catch { return {}; } }
  private save(): void {
    mkdirSync(dirname(this.path), { recursive: true }); const temporary = `${this.path}.tmp`;
    writeFileSync(temporary, JSON.stringify({ profile: "android-v1", device_id: this.deviceId, fp_device_id: this.fpDeviceId,
      device_name: this.deviceName, product_name: this.productName, device_fp: this.deviceFP }));
    chmodSync(temporary, 0o600); renameSync(temporary, this.path);
  }
}
