type QRStatus = "created" | "scanned" | "confirmed" | "expired";
export interface QRSession { id: string; url: string; status: QRStatus; expires_at: string; credential?: string | null }
export interface AccountIdentity { aid: string; mid: string; nickname: string; credential: string }
export interface MobileCaptchaVerification { gt: string; challenge: string; session_id: string }
export interface MobileCaptchaSession {
  mobile: string; action_type: string; countdown: number; aigis?: string | null;
  verification?: MobileCaptchaVerification | null;
}
export interface Account { aid: string; mid: string; nickname: string; credential_ref: string; selected: boolean; updated_at: string }
export interface GameRole { uid: string; nickname: string; region: string; level: number; selected: boolean }
export interface WishRecord {
  id: string; uid: string; gacha_type: string; uigf_gacha_type: string;
  item_id: string; name: string; item_type: string; rank: number; time: string; icon_url?: string | null;
}
export interface WishStatistics { uid: string; gacha_type: string; total: number; five_star_count: number; pulls_since_five_star: number }
interface WishTaskLog { sequence: number; message: string; emphasized: boolean }
export interface WishTask {
  id: string; kind: string; status: "queued" | "running" | "completed" | "failed";
  progress: number | null; logs: WishTaskLog[]; result: Record<string, number> | null; error: string; error_code?: string;
  revision?: number;
}
export interface CompanionSnapshot {
  wishes: WishRecord[]; statistics: WishStatistics[]; banner_statistics: unknown[]; note: DailyNote | null;
}
export interface DailyNote {
  uid: string; current_resin: number; max_resin: number; finished_tasks: number; total_tasks: number;
  expeditions_finished: number; expeditions_total: number; current_home_coin: number; max_home_coin: number;
  weekly_boss_remaining: number; transformer_ready: boolean; refreshed_at: string;
}
export interface GameCharacter {
  uid: string; avatar_id: string; name: string; element: string; level: number; rarity: number;
  constellation: number; fetter: number; weapon_name: string; weapon_level: number;
  icon_url?: string | null; payload: unknown; updated_at: string;
}
export interface AchievementArchive {
  id: string; name: string; selected: boolean; created_at: string; updated_at: string;
}
export interface AchievementItem {
  archive_id: string; achievement_id: number; current: number; status: number;
  timestamp: number; updated_at: string;
}
export interface AchievementGoal {
  id: number; order: number; name: string; reward_count: number; icon_url: string;
}
export interface AchievementViewItem extends AchievementItem {
  goal: number; order: number; title: string; description: string; progress: number;
  version: string; reward_count: number; icon_url: string; is_daily_quest: boolean;
}
export interface GachaEvent {
  id: string; version: string; gacha_type: string; name: string;
  started_at: string; ended_at: string; orange_up: string[]; purple_up: string[];
  banner_url?: string | null; updated_at: string;
}
export interface NotificationSettings {
  daily_commission_enabled: boolean; daily_commission_time: string; resin_full_enabled: boolean;
  gacha_refresh_enabled: boolean; version_update_enabled: boolean;
}
export interface NotificationEvent {
  key: string; title: string; body: string; destination: string; created_at: string;
}
export interface CloudLoginResult {
  uid: string; token: string; token_ref: string; reverified_at: string;
}
type GameStatus = "not_installed" | "ready" | "update_available" | "busy" | "damaged";
export interface GameState {
  install_path: string; installed_version: string; available_version: string; status: GameStatus;
  update_kind: string; download_bytes: number;
  predownload_version: string | null; predownload_finished: boolean;
}
export type JobKind = "install" | "update" | "verify" | "predownload";
type JobStatus = "queued" | "running" | "paused" | "completed" | "cancelled" | "failed";
interface ChunkProgress { name: string; bytes_done: number; total: number }
export interface GameJob {
  id: string; kind: JobKind; status: JobStatus; completed_bytes: number; total_bytes: number;
  message: string; download_speed: number; chunks_completed: number; chunks_total: number;
  active_chunks: ChunkProgress[]; last_update: string; revision?: number;
}
export interface PredownloadStatus { tag: string; finished: boolean; total_chunks: number }
export type GameLaunchStatus = "preparing" | "starting" | "waiting_window" | "running" | "stopping" | "stopped" | "exited" | "failed";
export type GamePerformanceProfile = "optimized" | "compatibility" | "baseline";
interface GameLaunchLog { sequence: number; timestamp: string; kind: "launch" | "dns" | "wine"; message: string }
export interface GameLaunch {
  id: string; status: GameLaunchStatus; message: string; performance_profile: GamePerformanceProfile;
  metal_hud: boolean; network_debug: boolean; wine_log: boolean; progress: number; logs: GameLaunchLog[];
  started_at: string; updated_at: string; revision?: number;
}
