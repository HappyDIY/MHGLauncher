import type { CycleKind, CycleRecord, GameCharacter, GameRole, GachaEvent, WishRecord } from "../core/models";

export interface GachaUrlProof {
  uid: string;
  records: WishRecord[];
}

export interface GameRecordSource {
  characters(credential: string, role: GameRole): Promise<GameCharacter[]>;
  characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter>;
  cycles(credential: string, role: GameRole, kind: CycleKind): Promise<CycleRecord[]>;
  gachaEvents(credential: string, role: GameRole): Promise<GachaEvent[]>;
  verifyGachaUrl(url: string): Promise<GachaUrlProof>;
}

export function cycleTitle(kind: CycleKind): string {
  if (kind === "abyss") return "深境螺旋";
  if (kind === "theatre") return "幻想真境剧诗";
  return "幽境危战";
}
