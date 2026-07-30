import {
  lstatSync, mkdirSync, realpathSync, symlinkSync, unlinkSync,
} from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";

const LINK_NAME = "game";

export function createGameLaunchLink(gameRoot: string, sessionDir: string): string {
  mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
  const link = join(sessionDir, LINK_NAME);
  try {
    lstatSync(link);
    throw new AppError("game_launch_link_exists", "游戏启动软链接已存在", 409);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  symlinkSync(realpathSync(gameRoot), link, "dir");
  return link;
}

export function removeGameLaunchLink(link: string): void {
  try {
    if (!lstatSync(link).isSymbolicLink()) {
      throw new AppError("game_launch_link_invalid", "游戏启动软链接已被替换", 500);
    }
    unlinkSync(link);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}
