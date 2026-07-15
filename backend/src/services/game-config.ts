import { existsSync, readFileSync } from "node:fs";
import { managedPath, writeManagedFile } from "./managed-file";

const DEFAULT_CONFIGURATION = `[general]
uapc={"hk4e_cn":{"uapc":""},"hyp":{"uapc":""}}
channel=1
sub_channel=1
cps=gw_pc
game_version={version}
`;

export function ensureGameConfiguration(root: string, version: string): void {
  const path = managedPath(root, "config.ini");
  if (!existsSync(path)) {
    writeManagedFile(root, "config.ini", DEFAULT_CONFIGURATION.replace("{version}", version));
    return;
  }
  const source = readFileSync(path, "utf8");
  const line = `game_version=${version}`;
  const updated = /^game_version\s*=.*$/im.test(source)
    ? source.replace(/^game_version\s*=.*$/im, line)
    : `${source.trimEnd()}\n${line}\n`;
  if (updated !== source) writeManagedFile(root, "config.ini", updated);
}
