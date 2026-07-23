import { z } from "zod";

const account = z.object({
  aid: z.string(), mid: z.string(), nickname: z.string(), credential_ref: z.string(),
  selected: z.boolean(), updated_at: z.string(),
}).strict();
const wish = z.object({
  id: z.string(), uid: z.string(), gacha_type: z.string(), uigf_gacha_type: z.string(),
  item_id: z.string(), name: z.string(), item_type: z.string(), rank: z.number(),
  time: z.string(), icon_url: z.string().nullable().optional(),
}).strict();
const dailyNote = z.object({
  uid: z.string(), current_resin: z.number(), max_resin: z.number(),
  finished_tasks: z.number(), total_tasks: z.number(), extra_task_reward_received: z.boolean(),
  expeditions_finished: z.number(), expeditions_total: z.number(),
  current_home_coin: z.number(), max_home_coin: z.number(),
  weekly_boss_remaining: z.number(), transformer_ready: z.boolean(), refreshed_at: z.string(),
}).strict();
const gameState = z.object({
  install_path: z.string(), installed_version: z.string(), available_version: z.string(),
  status: z.enum(["not_installed", "ready", "update_available", "busy", "damaged"]),
  update_kind: z.string(), download_bytes: z.number(),
  predownload_version: z.string().nullable(), predownload_finished: z.boolean(),
}).strict();
const gameJob = z.object({
  id: z.string(), kind: z.enum(["install", "update", "verify", "predownload"]),
  status: z.enum(["queued", "running", "pausing", "paused", "cancelling", "completed", "cancelled", "failed"]),
  completed_bytes: z.number(), total_bytes: z.number(), message: z.string(),
  download_speed: z.number(), chunks_completed: z.number(), chunks_total: z.number(),
  active_chunks: z.array(z.object({ name: z.string(), bytes_done: z.number(), total: z.number() }).strict()),
  last_update: z.string(), revision: z.number().optional(),
}).strict();
const gameLaunch = z.object({
  id: z.string(), status: z.enum(["preparing", "starting", "waiting_window", "running", "stopping", "stopped", "exited", "failed"]),
  message: z.string(), performance_profile: z.enum(["optimized", "compatibility", "baseline"]),
  metal_hud: z.boolean(), network_debug: z.boolean(), wine_log: z.boolean(),
  progress: z.number(), logs: z.array(z.object({
    sequence: z.number(), timestamp: z.string(), kind: z.enum(["launch", "dns", "wine"]), message: z.string(),
  }).strict()), started_at: z.string(), updated_at: z.string(), revision: z.number().optional(),
}).strict();
const wishTask = z.object({
  id: z.string(), kind: z.string(), status: z.enum(["queued", "running", "completed", "failed"]),
  progress: z.number().nullable(), logs: z.array(z.object({
    sequence: z.number(), message: z.string(), emphasized: z.boolean(),
  }).strict()), result: z.record(z.string(), z.number()).nullable(), error: z.string(),
  error_code: z.string().optional(), target_uids: z.array(z.string()).optional(),
  revision: z.number().optional(),
}).strict();

export const contractResponseSchemas = {
  account,
  api_error: z.object({
    code: z.string(), message: z.string(), details: z.record(z.string(), z.unknown()).nullable(),
  }).strict(),
  companion_snapshot: z.object({
    wishes: z.array(wish), statistics: z.array(z.unknown()),
    banner_statistics: z.array(z.unknown()), note: dailyNote.nullable(),
  }).strict(),
  daily_note: dailyNote,
  game_job: gameJob,
  game_launch: gameLaunch,
  game_state: gameState,
  wish_task: wishTask,
} as const;

export const localApiEndpoints = [
  ["GET", "/health"], ["GET", "/v1/app-update"], ["GET", "/v1/accounts"],
  ["GET", "/v1/account"], ["DELETE", "/v1/account"], ["POST", "/v1/account/select"],
  ["GET", "/v1/roles"], ["POST", "/v1/roles/select"], ["POST", "/v1/roles/sync"],
  ["POST", "/v1/auth/qr-sessions"], ["GET", "/v1/auth/qr-sessions/{id}"],
  ["POST", "/v1/auth/mobile-captcha"], ["POST", "/v1/auth/mobile-captcha/verification"],
  ["POST", "/v1/auth/mobile-login"], ["POST", "/v1/auth/cookie-login"],
  ["POST", "/v1/auth/commit"], ["POST", "/v1/auth/abort"],
  ["GET", "/v1/game/status"], ["GET", "/v1/game/status/path"],
  ["GET", "/v1/game/space-check"], ["POST", "/v1/game/jobs"],
  ["GET", "/v1/game/jobs/{id}"], ["POST", "/v1/game/jobs/{id}/control"],
  ["GET", "/v1/settings/speed-limit"], ["POST", "/v1/settings/speed-limit"],
  ["POST", "/v1/game/launch"], ["POST", "/v1/game/launches/{id}/stop"],
  ["GET", "/v1/game/launches/recovery"], ["GET", "/v1/game/launches/{id}"],
  ["POST", "/v1/wishes/tasks/sync"], ["POST", "/v1/wishes/tasks/import"],
  ["POST", "/v1/wishes/tasks/import-url"], ["GET", "/v1/wishes/tasks/{id}"],
  ["GET", "/v1/companion/snapshot"], ["GET", "/v1/wishes"],
  ["GET", "/v1/wishes/statistics"], ["GET", "/v1/wishes/banner-statistics"],
  ["DELETE", "/v1/wishes"], ["GET", "/v1/wishes/export"],
  ["GET", "/v1/notes"], ["POST", "/v1/notes/refresh"], ["POST", "/v1/notes/verification"],
  ["GET", "/v1/characters"], ["POST", "/v1/characters/cache-assets"],
  ["POST", "/v1/characters/refresh"], ["POST", "/v1/characters/{avatar_id}/refresh"],
  ["GET", "/v1/gacha-events"], ["GET", "/v1/gacha-resources/status"],
  ["POST", "/v1/gacha-resources/install"], ["GET", "/v1/gacha-resources/files/{path}"],
  ["GET", "/v1/gacha-resources/cache/{path}"], ["GET", "/v1/achievements/resources/icons/{name}.png"],
  ["GET", "/v1/achievements/archive"], ["GET", "/v1/achievements/goals"],
  ["GET", "/v1/achievements/view"], ["GET", "/v1/achievements/snapshot"],
  ["GET", "/v1/achievements"], ["POST", "/v1/achievements"],
  ["POST", "/v1/achievements/import"], ["GET", "/v1/achievements/export"],
  ["POST", "/v1/cloud/login"], ["POST", "/v1/cloud/login/account"],
  ["POST", "/v1/cloud/reverify"], ["GET", "/v1/cloud/session"],
  ["POST", "/v1/cloud/wishes/upload"], ["POST", "/v1/cloud/wishes/retrieve"],
  ["POST", "/v1/cloud/achievements/upload"], ["POST", "/v1/cloud/achievements/retrieve"],
  ["POST", "/v1/cloud/wishes/delete"], ["POST", "/v1/cloud/revoke"],
  ["GET", "/v1/notifications/settings"], ["PUT", "/v1/notifications/settings"],
  ["POST", "/v1/notifications/acknowledge"], ["POST", "/v1/notifications/evaluate"],
  ["GET", "/v1/wishes/export-uigf"],
] as const;
