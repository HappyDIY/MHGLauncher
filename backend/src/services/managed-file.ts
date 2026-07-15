import { closeSync, constants, openSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { containedPath } from "../core/safe-path";

export function managedPath(root: string, name: string): string {
  return containedPath(root, name);
}

export function writeManagedFile(root: string, name: string, value: string | Uint8Array): void {
  const target = managedPath(root, name);
  const temporary = containedPath(root, `.${name}.${randomUUID()}.tmp`);
  const descriptor = openSync(
    temporary,
    constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
    0o600,
  );
  try { writeFileSync(descriptor, value); } finally { closeSync(descriptor); }
  try { renameSync(temporary, target); } finally { rmSync(temporary, { force: true }); }
}
