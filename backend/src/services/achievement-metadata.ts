type Reward = { Count?: number };

export type AchievementGoalMetadata = {
  Id: number;
  Order: number;
  Name: string;
  FinishReward?: Reward;
  Icon: string;
};

export type AchievementMetadata = {
  Id: number;
  Goal: number;
  Order: number;
  Title: string;
  Description: string;
  FinishReward?: Reward;
  Progress: number;
  Version: string;
  Icon?: string;
  IsDailyQuest?: boolean;
};

export type AchievementMetadataBundle = {
  achievements: AchievementMetadata[];
  goals: AchievementGoalMetadata[];
};

export function parseAchievementMetadata(value: string, kind: "achievements"): AchievementMetadata[];
export function parseAchievementMetadata(value: string, kind: "goals"): AchievementGoalMetadata[];
export function parseAchievementMetadata(
  value: string,
  kind: "achievements" | "goals",
): AchievementMetadata[] | AchievementGoalMetadata[];
export function parseAchievementMetadata(
  value: string,
  kind: "achievements" | "goals",
): AchievementMetadata[] | AchievementGoalMetadata[] {
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed) || parsed.length > 20_000) throw new Error("invalid achievement metadata");
  const valid = kind === "achievements" ? parsed.every(validAchievement) : parsed.every(validGoal);
  if (!valid) throw new Error("invalid achievement metadata");
  return parsed as AchievementMetadata[] | AchievementGoalMetadata[];
}

function validAchievement(value: unknown): value is AchievementMetadata {
  if (!value || typeof value !== "object") return false;
  const item = value as Record<string, unknown>;
  return ["Id", "Goal", "Order", "Progress"].every((key) => Number.isSafeInteger(item[key]))
    && ["Title", "Description", "Version"].every((key) => typeof item[key] === "string");
}

function validGoal(value: unknown): value is AchievementGoalMetadata {
  if (!value || typeof value !== "object") return false;
  const item = value as Record<string, unknown>;
  return ["Id", "Order"].every((key) => Number.isSafeInteger(item[key]))
    && typeof item.Name === "string" && typeof item.Icon === "string";
}
