import type { GameCharacter, GameRole, WishRecord } from "../core/models";

export interface GachaUrlProof {
  uid: string;
  records: WishRecord[];
}

export interface GameRecordSource {
  characters(credential: string, role: GameRole): Promise<GameCharacter[]>;
  characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter>;
  verifyGachaUrl(url: string): Promise<GachaUrlProof>;
  wishesFromGachaUrl(url: string): AsyncIterable<WishRecord[]>;
}
