import type { GameCharacter, GameRole, GachaEvent, WishRecord } from "../core/models";

export interface GachaUrlProof {
  uid: string;
  records: WishRecord[];
}

export interface GameRecordSource {
  characters(credential: string, role: GameRole): Promise<GameCharacter[]>;
  characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter>;
  gachaEvents(credential: string, role: GameRole): Promise<GachaEvent[]>;
  verifyGachaUrl(url: string): Promise<GachaUrlProof>;
}
