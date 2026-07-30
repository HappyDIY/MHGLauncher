import { spawn, type ChildProcess } from "node:child_process";
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
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
      const wineArgs = opensPrefix ? [] : wineToolArguments(input);
      const wineEnv = prefixEnvironment(process.env, prefix, input.performance_profile);
      const opensConsole = isInteractiveConsole(wineArgs);
      const executable = opensPrefix || opensConsole ? "/usr/bin/open" : paths.wine;
      const args = opensPrefix
        ? [join(prefix, "drive_c")]
        : opensConsole
          ? [createConsoleLauncher(this.dataDir, paths.wine, wineArgs, wineEnv)]
          : wineArgs;
      const env = opensPrefix || opensConsole ? process.env : wineEnv;
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
  if (input.action === "preferences") {
    const version = input.command ?? "win10";
    if (!["win10", "win81", "win7"].includes(version)) {
      throw new AppError("wine_version_invalid", "不支持所选的 Windows 版本", 422);
    }
    return ["winecfg.exe", "/v", version];
  }
  const command = input.command?.trim();
  if (!command) throw new AppError("wine_command_missing", "请输入要运行的 Windows 命令", 422);
  return parseArgsStringToArgv(command);
}

function isInteractiveConsole(args: string[]): boolean {
  const executable = args[0]?.split(/[\\/]/).at(-1)?.toLowerCase();
  return executable === "cmd" || executable === "cmd.exe";
}

function createConsoleLauncher(
  dataDir: string, wine: string, args: string[], env: NodeJS.ProcessEnv,
): string {
  const directory = join(dataDir, "wine-tools");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const path = join(directory, `console-${randomUUID()}.command`);
  const values = Object.entries(env).filter((entry): entry is [string, string] => entry[1] !== undefined);
  const command = ["/usr/bin/env", ...values.map(([key, value]) => `${key}=${value}`), wine, ...args];
  const body = `#!/bin/zsh\nrm -f -- "$0"\nexec ${command.map(shellQuote).join(" ")}\n`;
  writeFileSync(path, body, { mode: 0o700 });
  chmodSync(path, 0o700);
  return path;
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function waitForSpawn(child: ChildProcess): Promise<void> {
  return new Promise((resolve, reject) => {
    child.once("spawn", resolve); child.once("error", reject);
  });
}
