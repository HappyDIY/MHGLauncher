import type { AccountIdentity, DailyNote, GameRole, MobileCaptchaSession, QRSession, WishRecord } from "../core/models";
import { safeIdentifier } from "../core/safe-path";

export interface PackageSegment { url: string; md5: string; size: number; filename: string }
export interface SophonChunk { name: string; decompressed_md5: string; offset: number; size: number; decompressed_size: number; url: string }
export interface GameAsset {
  name: string; size: number; md5: string; chunks: SophonChunk[];
  required_chunks?: SophonChunk[];
}
export interface SophonPatch { id: string; file_size: number; start: number; length: number; original_name: string; url: string }
export interface GamePatchAsset { name: string; size: number; md5: string; patch: SophonPatch }
export interface GameBuild {
  version: string; kind: string; pending_bytes: number; segments: PackageSegment[];
  assets: GameAsset[]; patch_assets: GamePatchAsset[]; deprecated_files: string[];
  base_assets: GameAsset[]; repair_assets: GameAsset[];
  is_predownload?: boolean;
}

export interface Provider {
  createQRSession(): Promise<QRSession>;
  queryQRSession(id: string): Promise<[QRSession, AccountIdentity | null]>;
  identifyCredential(credential: string): Promise<AccountIdentity>;
  createMobileCaptcha(mobile: string): Promise<MobileCaptchaSession>;
  verifyMobileCaptcha(mobile: string, sessionId: string, challenge: string, validate: string): Promise<MobileCaptchaSession>;
  loginByMobileCaptcha(mobile: string, captcha: string, actionType: string, aigis?: string | null): Promise<AccountIdentity>;
  getRoles(credential: string): Promise<GameRole[]>;
  getBuild(installedVersion?: string, audioLanguages?: string[]): Promise<GameBuild>;
  getInstalledBuild(installedVersion: string, audioLanguages?: string[]): Promise<GameBuild>;
  getPredownloadBuild(installedVersion?: string, audioLanguages?: string[]): Promise<GameBuild | null>;
  gachaUrl(credential: string, role: GameRole): Promise<string>;
  wishes(credential: string, role: GameRole, newest: Record<string, string>): AsyncIterable<WishRecord[]>;
  getDailyNote(credential: string, role: GameRole, challenge?: string, challengePath?: string): Promise<DailyNote>;
  verifyNoteChallenge(credential: string, challenge: string, validate: string, challengePath?: string): Promise<string>;
  createAuthTicket(credential: string): Promise<string>;
}

export function normalizeBuild(value: Partial<GameBuild> & Pick<GameBuild, "version">): GameBuild {
  return {
    version: safeIdentifier(value.version, "游戏版本"), kind: value.kind ?? "full", pending_bytes: value.pending_bytes ?? 0,
    segments: value.segments ?? [], assets: value.assets ?? [], patch_assets: value.patch_assets ?? [],
    base_assets: value.base_assets ?? [], repair_assets: value.repair_assets ?? [],
    deprecated_files: value.deprecated_files ?? [], is_predownload: value.is_predownload ?? false,
  };
}
