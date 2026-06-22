import { z } from "zod";
import { AppError } from "../core/errors";
import type { WishRecord } from "../core/models";
import { enrich } from "./metadata";

const item = z.object({
  id: z.coerce.string().regex(/^\d{1,19}$/), uigf_gacha_type: z.coerce.string(),
  gacha_type: z.coerce.string(), item_id: z.coerce.string(), time: z.string(),
  name: z.string().default(""), item_type: z.string().default(""),
  rank_type: z.coerce.string().optional(),
}).passthrough();
const account = z.object({ uid: z.coerce.string(), list: z.array(item) }).passthrough();
const modern = z.object({ info: z.object({ version: z.enum(["v4.0", "v4.1", "v4.2"]) }).passthrough(), hk4e: z.array(account).default([]) }).passthrough();
const legacy = z.object({
  info: z.object({ uid: z.coerce.string(), uigf_version: z.string().regex(/^v[23]\./) }).passthrough(),
  list: z.array(item).default([]),
}).passthrough();
const gachaTypes = new Set(["100", "200", "301", "302", "400", "500"]);
const uigfTypes = new Set(["100", "200", "301", "302", "500"]);

export function importUIGF(payload: unknown): WishRecord[] {
  try {
    const raw = payload as { info?: { uigf_version?: string } };
    const groups: { uid: string; list: z.infer<typeof item>[] }[] = raw.info?.uigf_version
      ? ((value) => [{ uid: value.info.uid, list: value.list }])(legacy.parse(payload))
      : modern.parse(payload).hk4e;
    const records = groups.flatMap((group) => group.list.map((value) => record(group.uid, value)));
    if (!records.length) throw new AppError("uigf_empty", "UIGF 文件不包含原神祈愿记录");
    return records;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError("uigf_invalid", "UIGF 文件不符合受支持的规范");
  }
}

export function exportUIGF(uid: string, records: WishRecord[]): Record<string, unknown> {
  return {
    info: { export_timestamp: Math.floor(Date.now() / 1000), export_app: "MHGLauncher", export_app_version: "1.0.0", version: "v4.2" },
    hk4e: [{ uid, timezone: uid.startsWith("6") ? -5 : uid.startsWith("7") ? 1 : 8, lang: "zh-cn", list: records.toReversed().map(exportItem) }],
  };
}

function record(uid: string, value: z.infer<typeof item>): WishRecord {
  if (!gachaTypes.has(value.gacha_type) || !uigfTypes.has(value.uigf_gacha_type) || Number.isNaN(Date.parse(value.time.replace(" ", "T")))) {
    throw new AppError("uigf_item_invalid", "UIGF 记录字段无效");
  }
  return enrich({
    id: value.id, uid, gacha_type: value.gacha_type, uigf_gacha_type: value.uigf_gacha_type,
    item_id: value.item_id, name: value.name, item_type: value.item_type,
    rank: Number(value.rank_type ?? 0), time: value.time.replace(" ", "T"),
  });
}

function exportItem(value: WishRecord): Record<string, string> {
  const result: Record<string, string> = {
    uigf_gacha_type: value.uigf_gacha_type || (value.gacha_type === "400" ? "301" : value.gacha_type),
    gacha_type: value.gacha_type, item_id: value.item_id, count: "1", time: value.time.replace("T", " ").slice(0, 19), id: value.id,
  };
  if (value.name) result.name = value.name;
  if (value.item_type) result.item_type = value.item_type;
  if (value.rank) result.rank_type = String(value.rank);
  return result;
}
