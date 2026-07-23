import { z } from "zod";

export const credentialRequest = z.object({
  credential: z.string().min(1).max(16_384),
}).strict();
export const gachaUrlRequest = z.object({
  gacha_url: z.string().url().max(16_384),
}).strict();
export const roleSyncRequest = z.object({
  aid: z.string().min(1).max(32),
  credential: z.string().min(1).max(16_384),
}).strict();
export const selectAccountRequest = z.object({ aid: z.string().min(1).max(32) }).strict();
export const selectRoleRequest = z.object({ uid: z.string().regex(/^\d{9,10}$/) }).strict();
export const mobileRequest = z.object({ mobile: z.string().regex(/^1\d{10}$/) }).strict();
export const mobileLoginRequest = z.object({
  mobile: z.string().regex(/^1\d{10}$/), captcha: z.string().min(4).max(16),
  action_type: z.string().min(1).max(128), aigis: z.string().max(16_384).optional().nullable(),
}).strict();
export const mobileVerificationRequest = z.object({
  mobile: z.string().regex(/^1\d{10}$/), session_id: z.string().min(1).max(256),
  challenge: z.string().min(1).max(4096), validate: z.string().min(1).max(4096),
}).strict();
export const loginTransactionRequest = z.object({ transaction_id: z.string().uuid() }).strict();
export const noteRefreshRequest = z.object({
  credential: z.string().max(16_384), xrpc_challenge: z.string().max(4096).default(""),
  xrpc_challenge_path: z.string().max(2048).default(""),
}).strict();
export const noteVerificationRequest = z.object({
  credential: z.string().max(16_384), challenge: z.string().max(4096),
  validate: z.string().max(4096), xrpc_challenge_path: z.string().max(2048).default(""),
}).strict();
export const startJobRequest = z.object({
  kind: z.enum(["install", "update", "verify", "predownload"]),
  install_path: z.string().min(1).max(4096),
}).strict();
export const controlJobRequest = z.object({
  action: z.enum(["pause", "resume", "cancel"]),
}).strict();
export const speedLimitRequest = z.object({
  speed_limit_kb: z.number().int().min(0).max(10_000_000),
}).strict();
export const startLaunchRequest = z.object({
  install_path: z.string().min(1).max(4096),
  performance_profile: z.enum(["optimized", "compatibility", "baseline"]).default("optimized"),
  metal_hud: z.boolean().default(false), network_debug: z.boolean().default(false),
  wine_log: z.boolean().default(false), frame_pacing: z.number().int().min(0).max(240).default(0),
  credential: z.string().min(1).max(16_384).optional(),
}).strict();
export const cloudUidRequest = z.object({
  uid: z.string().regex(/^\d{9,10}$/), token: z.string().min(1).max(1024),
}).strict();
export const cloudGachaUrlRequest = z.object({
  gacha_url: z.string().url().max(16_384),
  token: z.string().max(1024).optional().default(""),
}).strict();
export const achievementSaveRequest = z.object({
  archive_id: z.string().min(1), expected_revision: z.number().int().min(0),
  items: z.array(z.object({
    achievement_id: z.number().int(), current: z.number().int(),
    status: z.number().int(), timestamp: z.number().int(),
  }).strict()).max(200_000),
}).strict();
export const notificationSettingsRequest = z.object({
  daily_commission_enabled: z.boolean().optional(),
  daily_commission_time: z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/).optional(),
  resin_full_enabled: z.boolean().optional(), gacha_refresh_enabled: z.boolean().optional(),
  version_update_enabled: z.boolean().optional(),
}).strict();
export const notificationAcknowledgementRequest = z.object({
  keys: z.array(z.string().regex(/^[A-Za-z0-9:._-]{1,160}$/)).max(20),
}).strict();

export const contractRequestSchemas = {
  achievement_save: achievementSaveRequest,
  cloud_uid: cloudUidRequest,
  control_job: controlJobRequest,
  credential: credentialRequest,
  login_transaction: loginTransactionRequest,
  note_refresh: noteRefreshRequest,
  note_verification: noteVerificationRequest,
  notification_acknowledgement: notificationAcknowledgementRequest,
  notification_settings: notificationSettingsRequest,
  speed_limit: speedLimitRequest,
  start_job: startJobRequest,
  start_launch: startLaunchRequest,
} as const;
