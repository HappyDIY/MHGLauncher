import { ftruncateSync } from "node:fs";

export function preallocateFileDescriptor(fd: number, size: number): void {
  ftruncateSync(fd, size);
}