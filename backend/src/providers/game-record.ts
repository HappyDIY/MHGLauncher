import type { GameCharacter, GameRole } from "../core/models";

export interface GameRecordSource {
  characters(credential: string, role: GameRole): Promise<GameCharacter[]>;
  characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter>;
}
