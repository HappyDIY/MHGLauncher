import { chmod } from "node:fs/promises";
import { createServer } from "node:http";
import next from "next";
import { closeContainer, container } from "./src/core/container";
import { validateServerSettings } from "./src/core/config";
import { releaseSocket, requireUnusedSocketPath, socketIdentity } from "./src/core/server-socket";

const config = container().settings;
validateServerSettings(config);
const application = next({ dev: process.env.NODE_ENV !== "production", dir: process.cwd() });
await application.prepare();
await requireUnusedSocketPath(config.socketPath);
const server = createServer(application.getRequestHandler());
server.requestTimeout = config.requestTimeout;
server.headersTimeout = Math.min(config.requestTimeout, 60_000);

await new Promise<void>((resolve, reject) => {
  server.once("error", reject);
  server.listen(config.socketPath, 128, () => resolve());
});
await chmod(config.socketPath, 0o600);
const listeningSocket = await socketIdentity(config.socketPath);
process.stdout.write(`${JSON.stringify({ event: "ready", socket_path: config.socketPath })}\n`);

let closing = false;
async function shutdown(): Promise<void> {
  if (closing) return;
  closing = true;
  clearInterval(parentMonitor);
  const closed = new Promise<void>((resolve) => server.close(() => resolve()));
  const deadline = setTimeout(() => server.closeAllConnections(), config.requestTimeout);
  deadline.unref();
  await closed;
  clearTimeout(deadline);
  closeContainer();
  await releaseSocket(config.socketPath, listeningSocket);
}

const expectedParent = Number(process.env.MHG_PARENT_PID ?? 0);
const parentMonitor = setInterval(() => {
  if (expectedParent && process.ppid !== expectedParent) void shutdown().then(() => process.exit(0));
}, 1_000);
parentMonitor.unref();

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => void shutdown().then(() => process.exit(0)));
}
