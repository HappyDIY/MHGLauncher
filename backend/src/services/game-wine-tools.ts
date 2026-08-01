import { spawn, type ChildProcess } from "node:child_process";
import { join } from "node:path";
import { parseArgsStringToArgv } from "string-argv";
import type { GamePerformanceProfile } from "../core/models";
import { AppError } from "../core/errors";
import { prefixEnvironment, prepareWinePrefix } from "./game-wine-prefix";

type WineToolAction = "explorer" | "preferences" | "run";
export interface WineToolInput {
  action: WineToolAction; command?: string; performance_profile: GamePerformanceProfile;
}
type SpawnTool = typeof spawn;

export class GameWineToolService {
  private starting = false;
  constructor(
    private readonly dataDir: string, private readonly runtimeRoot: string,
    private readonly gameActive: () => boolean, private readonly spawnTool: SpawnTool = spawn,
  ) {}

  async start(input: WineToolInput): Promise<void> {
    if (this.starting || this.gameActive()) {
      throw new AppError("wine_tool_busy", "游戏或其他 Wine 工具正在启动", 409);
    }
    this.starting = true;
    try {
      const { paths, prefix } = await prepareWinePrefix(
        this.runtimeRoot, this.dataDir, input.performance_profile, false,
      );
      const opensPrefix = input.action === "explorer";
      const executable = opensPrefix ? "/usr/bin/open" : paths.wine;
      const args = opensPrefix ? [join(prefix, "drive_c")] : wineToolLaunchArguments(input);
      const env = opensPrefix
        ? process.env
        : prefixEnvironment(process.env, prefix, input.performance_profile);
      const child = this.spawnTool(executable, args, {
        detached: true, env,
        stdio: "ignore",
      });
      await waitForSpawn(child); child.unref();
    } finally {
      this.starting = false;
    }
  }
}

export function wineToolArguments(input: WineToolInput): string[] {
  if (input.action === "preferences") return ["winecfg.exe"];
  const command = input.command?.trim();
  if (!command) throw new AppError("wine_command_missing", "请输入要运行的 Windows 命令", 422);
  return parseArgsStringToArgv(command);
}

export function wineToolLaunchArguments(input: WineToolInput): string[] {
  const args = wineToolArguments(input);
  const executable = args[0]?.split(/[\\/]/).at(-1)?.toLowerCase();
  return executable === "cmd" || executable === "cmd.exe"
    ? ["wineconsole.exe", ...args]
    : args;
}

function waitForSpawn(child: ChildProcess): Promise<void> {
  return new Promise((resolve, reject) => {
    child.once("spawn", resolve); child.once("error", reject);
  });
}
