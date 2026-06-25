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
}
export interface DailyNote {
  uid: string; current_resin: number; max_resin: number; finished_tasks: number; total_tasks: number;
  expeditions_finished: number; expeditions_total: number; current_home_coin: number; max_home_coin: number;
  weekly_boss_remaining: number; transformer_ready: boolean; refreshed_at: string;
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
  active_chunks: ChunkProgress[]; last_update: string;
}
export interface PredownloadStatus { tag: string; finished: boolean; total_chunks: number }
export type GameLaunchStatus = "preparing" | "starting" | "waiting_window" | "running" | "stopping" | "stopped" | "exited" | "failed";
export type GamePerformanceProfile = "optimized" | "compatibility" | "baseline";
interface GameLaunchLog { sequence: number; timestamp: string; kind: "launch" | "dns" | "wine"; message: string }
export interface GameLaunch {
  id: string; status: GameLaunchStatus; message: string; performance_profile: GamePerformanceProfile;
  metal_hud: boolean; network_debug: boolean; wine_log: boolean; progress: number; logs: GameLaunchLog[];
  started_at: string; updated_at: string;
}
