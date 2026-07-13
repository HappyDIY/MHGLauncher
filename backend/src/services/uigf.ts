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
const gameUid = z.coerce.string().regex(/^\d{9,10}$/);
const account = z.object({ uid: gameUid, timezone: z.coerce.number().int().min(-12).max(14).default(8), list: z.array(item) }).passthrough();
const modern = z.object({ info: z.object({ version: z.enum(["v4.0", "v4.1", "v4.2"]) }).passthrough(), hk4e: z.array(account).default([]) }).passthrough();
const legacy = z.object({
  info: z.object({ uid: gameUid, uigf_version: z.string().regex(/^v[23]\./) }).passthrough(),
  list: z.array(item).default([]),
}).passthrough();
const gachaTypes = new Set(["100", "200", "301", "302", "400", "500"]);
const uigfTypes = new Set(["100", "200", "301", "302", "500"]);

export function importUIGF(payload: unknown): WishRecord[] {
  try {
    const raw = payload as { info?: { uigf_version?: string } };
    const groups: { uid: string; timezone: number; list: z.infer<typeof item>[] }[] = raw.info?.uigf_version
      ? ((value) => [{ uid: value.info.uid, timezone: 8, list: value.list }])(legacy.parse(payload))
      : modern.parse(payload).hk4e;
    const records = groups.flatMap((group) => group.list.map((value) => record(group.uid, group.timezone, value)));
    if (!records.length) throw new AppError("uigf_empty", "UIGF 文件不包含原神祈愿记录");
    return records;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError("uigf_invalid", "UIGF 文件不符合受支持的规范");
  }
}

export function exportUIGF(uid: string, records: WishRecord[]): Record<string, unknown> {
  const timezone = uid.startsWith("6") ? -5 : uid.startsWith("7") ? 1 : 8;
  return {
    info: { export_timestamp: Math.floor(Date.now() / 1000), export_app: "MHGLauncher", export_app_version: "1.0.0", version: "v4.2" },
    hk4e: [{ uid, timezone, lang: "zh-cn", list: records.toReversed().map((value) => exportItem(value, timezone)) }],
  };
}

function record(uid: string, timezone: number, value: z.infer<typeof item>): WishRecord {
  const time = normalizeTime(value.time, timezone);
  if (!gachaTypes.has(value.gacha_type) || !uigfTypes.has(value.uigf_gacha_type) || !time) {
    throw new AppError("uigf_item_invalid", "UIGF 记录字段无效");
  }
  return enrich({
    id: value.id, uid, gacha_type: value.gacha_type, uigf_gacha_type: value.uigf_gacha_type,
    item_id: value.item_id, name: value.name, item_type: value.item_type,
    rank: Number(value.rank_type ?? 0), time,
  });
}

function normalizeTime(value: string, timezone: number): string | null {
  const candidate = value.trim().replace(" ", "T");
  const offset = timezone >= 0 ? `+${String(timezone).padStart(2, "0")}:00` : `-${String(-timezone).padStart(2, "0")}:00`;
  const source = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(candidate) ? candidate : `${candidate}${offset}`;
  const epoch = Date.parse(source);
  return Number.isFinite(epoch) ? new Date(epoch).toISOString() : null;
}

function exportItem(value: WishRecord, timezone: number): Record<string, string> {
  const epoch = Date.parse(value.time);
  const local = new Date(epoch + timezone * 3_600_000).toISOString().replace("T", " ").slice(0, 19);
  const result: Record<string, string> = {
    uigf_gacha_type: value.uigf_gacha_type || (value.gacha_type === "400" ? "301" : value.gacha_type),
    gacha_type: value.gacha_type, item_id: value.item_id, count: "1", time: local, id: value.id,
  };
  if (value.name) result.name = value.name;
  if (value.item_type) result.item_type = value.item_type;
  if (value.rank) result.rank_type = String(value.rank);
  return result;
}
