import { isAbsolute } from "node:path";
import { AppError } from "../core/errors";
import type { GameAsset, GamePatchAsset, SophonChunk } from "./provider";

const md5 = /^[a-f0-9]{32}$/i;
const identifier = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/;
const maxChunkOutput = 256 * 1024 * 1024;

export function validateSophonAssets(assets: GameAsset[]): GameAsset[] {
  const chunks = new Map<string, string>(), names = new Set<string>();
  for (const asset of assets) {
    if (!safePath(asset.name) || !integer(asset.size, 0) || !md5.test(asset.md5)) invalid();
    const name = asset.name.toLowerCase(); if (names.has(name)) invalid(); names.add(name);
    for (const chunk of asset.chunks) validateChunk(chunk, asset.size, chunks);
  }
  return assets;
}

export function validateSophonPatches(assets: GamePatchAsset[]): GamePatchAsset[] {
  const patches = new Map<string, string>(), names = new Set<string>();
  for (const asset of assets) {
    const patch = asset.patch;
    if (!safePath(asset.name) || !integer(asset.size, 0) || !md5.test(asset.md5)
      || !identifier.test(patch.id) || !integer(patch.file_size, 1) || !integer(patch.start, 0)
      || !integer(patch.length, 1) || patch.start + patch.length > patch.file_size
      || !safeRemoteURL(patch.url) || (patch.original_name !== "" && !safePath(patch.original_name))) invalid();
    const name = asset.name.toLowerCase(); if (names.has(name)) invalid(); names.add(name);
    const signature = JSON.stringify([patch.file_size]);
    if (patches.has(patch.id) && patches.get(patch.id) !== signature) invalid();
    patches.set(patch.id, signature);
  }
  return assets;
}

export function validateSophonPaths(paths: string[]): string[] {
  if (!paths.every(safePath)) invalid();
  return paths;
}

function validateChunk(chunk: SophonChunk, assetSize: number, known: Map<string, string>): void {
  if (!identifier.test(chunk.name) || !md5.test(chunk.decompressed_md5) || !integer(chunk.offset, 0)
    || !integer(chunk.size, 1) || !integer(chunk.decompressed_size, 0)
    || chunk.decompressed_size > maxChunkOutput || chunk.offset + chunk.decompressed_size > assetSize
    || !safeRemoteURL(chunk.url)) invalid();
  const signature = JSON.stringify([chunk.size, chunk.decompressed_size, chunk.decompressed_md5.toLowerCase()]);
  if (known.has(chunk.name) && known.get(chunk.name) !== signature) invalid();
  known.set(chunk.name, signature);
}

function integer(value: number, minimum: number): boolean {
  return Number.isSafeInteger(value) && value >= minimum;
}

function safePath(value: string): boolean {
  const normalized = value.replaceAll("\\", "/");
  return Boolean(normalized) && !normalized.includes("\0") && !isAbsolute(normalized)
    && normalized.split("/").every((part) => part !== "" && part !== "." && part !== "..");
}

function safeRemoteURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && Boolean(url.hostname) && !url.username && !url.password;
  } catch { return false; }
}

function invalid(): never {
  throw new AppError("sophon_manifest_invalid", "Sophon 资源清单包含无效字段", 502);
}
