import { spawn } from "node:child_process";

interface CommandOptions {
  env?: NodeJS.ProcessEnv; cwd?: string; input?: string; timeout?: number;
}
export interface CommandResult { status: number | null; stdout: string; stderr: string; error?: Error }

export function runCommand(command: string, args: string[], options: CommandOptions = {}): Promise<CommandResult> {
  return new Promise((resolve) => {
    let stdout = "", stderr = "", finished = false;
    const child = spawn(command, args, { env: options.env, cwd: options.cwd, stdio: ["pipe", "pipe", "pipe"] });
    const done = (result: CommandResult): void => { if (!finished) { finished = true; clearTimeout(timer); resolve(result); } };
    const append = (current: string, chunk: Buffer): string => `${current}${chunk.toString("utf8")}`.slice(-1024 * 1024);
    child.stdout.on("data", (chunk: Buffer) => { stdout = append(stdout, chunk); });
    child.stderr.on("data", (chunk: Buffer) => { stderr = append(stderr, chunk); });
    child.once("error", (error) => done({ status: null, stdout, stderr, error }));
    child.once("exit", (status) => done({ status, stdout, stderr }));
    if (options.input !== undefined) child.stdin.end(options.input); else child.stdin.end();
    const timer = setTimeout(() => {
      child.kill("SIGKILL"); done({ status: null, stdout, stderr, error: new Error("command timeout") });
    }, options.timeout ?? 30_000);
  });
}
