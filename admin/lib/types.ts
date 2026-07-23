export type Overview = {
  healthy: boolean; database: string;
  totals: { users: number; active_sessions: number; gacha_records: number; achievement_archives: number };
  current_release: { version: string; source: string; published_at: string | null } | null;
  recent_audit: AuditEvent[];
};

export type CloudUser = {
  uid: string; created_at: string; updated_at: string; total_sessions: number; active_sessions: number; gacha_count: number;
  latest_gacha: string | null; achievement_count: number; achievement_updated_at: string | null;
};

export type Release = {
  id: number; version: string; download_url: string; sha256: string; size: number; changelog: string;
  status: "draft" | "published" | "archived"; created_at: string; published_at: string | null;
};

export type AuditEvent = {
  id: number; actor: string; action: string; target_type: string; target_ref: string;
  result: "success" | "failure"; metadata?: Record<string, unknown>; created_at: string;
};
