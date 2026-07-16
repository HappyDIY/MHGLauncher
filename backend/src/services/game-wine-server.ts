import { AppError } from "../core/errors";
import { runCommand } from "./process-command";

export async function stopWineServer(wineserver: string, prefix: string): Promise<void> {
  const env = { ...process.env, WINEPREFIX: prefix, WINEDEBUG: "-all" };
  const stop = await runCommand(wineserver, ["-k"], { env });
  const alreadyStopped = stop.status === 1 && !stop.stderr.trim();
  const accepted = !stop.error && (stop.status === 0 || alreadyStopped);
  const wait = accepted ? await runCommand(wineserver, ["-w"], { env }) : null;
  if (!accepted || wait?.error || wait?.status !== 0) {
    throw new AppError("wine_server_stop_failed", "Wine 服务未能在期限内确认退出", 500);
  }
}
