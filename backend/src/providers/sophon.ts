import { createHash } from "node:crypto";
import { zstdDecompressSync } from "node:zlib";
import { parse } from "protobufjs";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GameAsset, GameBuild, GamePatchAsset, SophonPatch } from "./provider";
import { normalizeBuild } from "./provider";
import { diffGameBuild } from "./build-diff";
import { validateSophonAssets, validateSophonPatches, validateSophonPaths } from "./sophon-validation";

type JSONValue = Record<string, any>;
const proto = `syntax="proto3";
message AssetChunk { string chunk_name=1; string chunk_decompressed_hash_md5=2; int64 chunk_on_file_offset=3; int64 chunk_size=4; int64 chunk_size_decompressed=5; }
message AssetProperty { string asset_name=1; repeated AssetChunk asset_chunks=2; int32 asset_type=3; int64 asset_size=4; string asset_hash_md5=5; }
message SophonManifest { repeated AssetProperty assets=1; }
message PatchInfo { string id=1; int64 patch_file_size=4; int64 patch_start_offset=6; int64 patch_length=7; string original_file_name=8; }
message PatchesEntry { string key=1; PatchInfo patch_info=2; }
message PatchFileData { string file_name=1; int64 file_size=2; string file_hash=3; repeated PatchesEntry patches_entries=4; }
message FileInfo { string name=1; } message DeleteFiles { repeated FileInfo infos=1; }
message DeleteFilesEntry { string key=1; DeleteFiles delete_files=2; }
message PatchManifest { repeated PatchFileData file_datas=1; repeated DeleteFilesEntry delete_files_entries=2; }`;
const root = parse(proto, { keepCase: true }).root;
const MAX_METADATA_BYTES = 64 * 1024 * 1024, MAX_MANIFEST_BYTES = 64 * 1024 * 1024, MAX_DECOMPRESSED_BYTES = 256 * 1024 * 1024;
const DEFAULT_STALL_TIMEOUT_MS = 30_000;

export function decodeSophonManifest(buffer: Uint8Array): JSONValue {
  const model = root.lookupType("SophonManifest");
  return model.toObject(model.decode(buffer), { longs: Number, defaults: true }) as JSONValue;
}

export class Sophon {
  private cached?: { time: number; key: string; build: GameBuild };
  private branchesCache?: { time: number; value: { main: JSONValue; pre: JSONValue | null } };

  async build(version = "", audioLanguages = ["zh-cn"]): Promise<GameBuild> {
    const languages = [...new Set(audioLanguages)].sort(), key = `${version}:${languages.join(",")}`;
    if (this.cached?.key === key && Date.now() - this.cached.time < 300_000) return this.cached.build;
    const branch = await this.branch();
    const remote = await this.fullBuild(branch, languages);
    let build = remote;
    if ((branch.diff_tags as string[] ?? []).includes(version)) {
      const patch = await this.patchBuild(branch, version, languages);
      build = { ...patch, repair_assets: remote.assets };
    } else if (version && version !== remote.version) {
      try { build = diffGameBuild(await this.fullBuild(branch, languages, version), remote, "version_diff_chunks"); }
      catch { build = remote; }
    }
    this.cached = { time: Date.now(), key, build }; return build;
  }

  async predownloadBuild(version = "", audioLanguages = ["zh-cn"]): Promise<GameBuild | null> {
    const languages = [...new Set(audioLanguages)].sort();
    const { pre } = await this.branches();
    if (!pre) return null;
    const key = `pre:${version}:${languages.join(",")}`;
    if (this.cached?.key === key && Date.now() - this.cached.time < 300_000) return this.cached.build;
    const remote = await this.fullBuild(pre, languages);
    const build = (pre.diff_tags as string[] ?? []).includes(version)
      ? { ...await this.patchBuild(pre, version, languages), repair_assets: remote.assets } : remote;
    const result = { ...build, is_predownload: true };
    this.cached = { time: Date.now(), key, build: result }; return result;
  }

  async installedBuild(version: string, audioLanguages = ["zh-cn"]): Promise<GameBuild> {
    const languages = [...new Set(audioLanguages)].sort(), key = `installed:${version}:${languages.join(",")}`;
    if (this.cached?.key === key && Date.now() - this.cached.time < 300_000) return this.cached.build;
    const build = await this.fullBuild(await this.branch(), languages, version);
    this.cached = { time: Date.now(), key, build }; return build;
  }

  private async fullBuild(branch: JSONValue, languages: string[], tag?: string): Promise<GameBuild> {
    const query = new URLSearchParams({ branch: String(branch.branch), package_id: String(branch.package_id), password: String(branch.password) });
    if (String(branch.branch).toLowerCase() !== "predownload") query.set("tag", tag ?? String(branch.tag));
    const data = await this.data(`https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getBuild?${query}`);
    const selected = this.selected(data, languages); if (!selected.length) throw new AppError("sophon_build_empty", "Sophon 构建未包含所需资源清单", 502);
    const assets: GameAsset[] = [];
    for (const item of selected) assets.push(...await this.assets(item));
    if (!assets.length) throw new AppError("sophon_build_empty", "Sophon 构建资源为空", 502);
    const build = normalizeBuild({ version: String(data.tag), assets: validateSophonAssets(assets) });
    if (tag && build.version !== tag) throw new AppError("sophon_installed_build_missing", "未找到当前版本的完整资源清单", 409);
    return build;
  }

  private async patchBuild(branch: JSONValue, version: string, languages: string[]): Promise<GameBuild> {
    const data = await this.data("https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getPatchBuild", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(branch) });
    const patch_assets: GamePatchAsset[] = [], deprecated_files: string[] = [];
    const selected = this.selected(data, languages); if (!selected.length) throw new AppError("sophon_build_empty", "Sophon 差分构建未包含所需资源清单", 502);
    for (const item of selected) {
      const manifest = await this.manifest(item, "PatchManifest") as JSONValue;
      for (const file of manifest.file_datas as JSONValue[] ?? []) {
        const info = (file.patches_entries as JSONValue[] ?? []).find((entry) => entry.key === version)?.patch_info as JSONValue | undefined;
        if (!info) continue;
        const patch: SophonPatch = { id: String(info.id), file_size: Number(info.patch_file_size), start: Number(info.patch_start_offset), length: Number(info.patch_length), original_name: String(info.original_file_name ?? ""), url: this.url(item.diff_download as JSONValue, String(info.id)) };
        patch_assets.push({ name: String(file.file_name), size: Number(file.file_size), md5: String(file.file_hash), patch });
      }
      const deleted = (manifest.delete_files_entries as JSONValue[] ?? []).find((entry) => entry.key === version)?.delete_files?.infos as JSONValue[] | undefined;
      deprecated_files.push(...(deleted ?? []).map((value) => String(value.name)));
    }
    if (!patch_assets.length && !deprecated_files.length) throw new AppError("sophon_build_empty", "Sophon 差分构建不包含任何变更", 502);
    return normalizeBuild({
      version: String(data.tag), kind: "version_diff",
      patch_assets: validateSophonPatches(patch_assets), deprecated_files: validateSophonPaths(deprecated_files),
    });
  }

  private async branch(): Promise<JSONValue> {
    const { main } = await this.branches(); return main;
  }

  private async branches(): Promise<{ main: JSONValue; pre: JSONValue | null }> {
    if (this.branchesCache && Date.now() - this.branchesCache.time < 300_000) return this.branchesCache.value;
    const query = new URLSearchParams({ "game_ids[]": "1Z8W5NHUQb", launcher_id: "jGHBHlcOq1" });
    const data = await this.data(`https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGameBranches?${query}`);
    const entry = (data.game_branches as JSONValue[] | undefined)?.[0];
    const main = entry?.main as JSONValue | undefined;
    if (!main) throw new AppError("sophon_branch_missing", "未找到国服游戏分支", 502);
    const pre = (entry?.pre_download as JSONValue | undefined) ?? null;
    const result = { main, pre };
    this.branchesCache = { time: Date.now(), value: result }; return result;
  }

  private async assets(item: JSONValue): Promise<GameAsset[]> {
    const manifest = await this.manifest(item, "SophonManifest") as JSONValue;
    const values = manifest.assets as JSONValue[] ?? [];
    if (values.length > 200_000 || values.reduce((count, asset) => count + ((asset.asset_chunks as JSONValue[] | undefined)?.length ?? 0), 0) > 200_000) throw new AppError("sophon_manifest_too_large", "Sophon 清单条目过多", 502);
    return values.map((asset) => ({ name: String(asset.asset_name), size: Number(asset.asset_size), md5: String(asset.asset_hash_md5),
      chunks: (asset.asset_chunks as JSONValue[] ?? []).map((chunk) => ({ name: String(chunk.chunk_name), decompressed_md5: String(chunk.chunk_decompressed_hash_md5), offset: Number(chunk.chunk_on_file_offset), size: Number(chunk.chunk_size), decompressed_size: Number(chunk.chunk_size_decompressed), url: this.url(item.chunk_download as JSONValue, String(chunk.chunk_name)) })) }));
  }

  private async manifest(item: JSONValue, type: "SophonManifest" | "PatchManifest"): Promise<unknown> {
    const info = item.manifest as JSONValue, response = await fetchWithStall(this.url(item.manifest_download as JSONValue, String(info.id)));
    if (!response.ok) throw new AppError("sophon_manifest_invalid", "Sophon 清单下载失败", 502);
    const compressed = await readBoundedResponse(response, MAX_MANIFEST_BYTES);
    if (type === "SophonManifest") { const expected = String(info.id).replace("manifest_", "").split("_", 1)[0]; if ((await xxhash()).h64Raw(compressed).toString(16).padStart(16, "0") !== expected?.toLowerCase()) throw new AppError("sophon_manifest_invalid", "Sophon 清单校验失败", 502); }
    const decoded = decodeZstdLimited(compressed); if (createHash("md5").update(decoded).digest("hex") !== String(info.checksum).toLowerCase()) throw new AppError("sophon_manifest_invalid", "Sophon 清单内容校验失败", 502);
    if (type === "SophonManifest") return decodeSophonManifest(decoded);
    const model = root.lookupType(type); return model.toObject(model.decode(decoded), { longs: Number, defaults: true });
  }

  private selected(data: JSONValue, languages: string[]): JSONValue[] {
    const selected = new Set(["game", ...languages]);
    return (data.manifests as JSONValue[] ?? []).filter((item) => selected.has(String(item.matching_field)));
  }
  private url(download: JSONValue, name: string): string { const prefix = String(download.url_prefix).replace(/\/$/, ""), suffix = String(download.url_suffix ?? ""); return `${prefix}/${name}${suffix && !suffix.startsWith("?") ? "?" : ""}${suffix}`; }
  private async data(url: string, init?: RequestInit): Promise<JSONValue> {
    const response = await fetchWithStall(url, init); if (!response.ok) throw new AppError("mihoyo_error", "下载服务请求失败", 502);
    let payload: JSONValue; try { payload = JSON.parse((await readBoundedResponse(response, MAX_METADATA_BYTES)).toString("utf8")) as JSONValue; }
    catch (error) { if (error instanceof AppError) throw error; throw new AppError("sophon_metadata_invalid", "下载服务元数据无效", 502); }
    if (Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "下载服务请求失败"), 502);
    return payload.data as JSONValue ?? {};
  }
}

export async function readBoundedResponse(response: Response, maxBytes: number): Promise<Buffer> {
  const declared = response.headers.get("content-length");
  if (declared && Number(declared) > maxBytes) throw new AppError("sophon_response_too_large", "Sophon 响应超过大小限制", 502);
  if (!response.body) throw new AppError("sophon_response_invalid", "Sophon 响应缺少内容", 502);
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  while (true) {
    const { done, value } = await readWithStall(reader); if (done) break; total += value.length;
    if (total > maxBytes) { await reader.cancel(); throw new AppError("sophon_response_too_large", "Sophon 响应超过大小限制", 502); }
    chunks.push(value);
  }
  return Buffer.concat(chunks, total);
}

function stallTimeout(): number {
  const configured = Number(process.env.MHG_SOPHON_STALL_TIMEOUT_MS ?? DEFAULT_STALL_TIMEOUT_MS);
  return Number.isFinite(configured) ? Math.max(50, configured) : DEFAULT_STALL_TIMEOUT_MS;
}

function timeoutError(): AppError {
  return new AppError("sophon_timeout", "下载服务请求超时", 504);
}

async function fetchWithStall(url: string, init?: RequestInit): Promise<Response> {
  const stalled = new AbortController();
  const signal = init?.signal ? AbortSignal.any([init.signal, stalled.signal]) : stalled.signal;
  const timer = setTimeout(() => stalled.abort(), stallTimeout());
  try { return await fetch(url, { ...init, signal }); }
  catch (error) { if (stalled.signal.aborted) throw timeoutError(); throw error; }
  finally { clearTimeout(timer); }
}

async function readWithStall(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<ReadableStreamReadResult<Uint8Array>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      reader.read(),
      new Promise<never>((_resolve, reject) => { timer = setTimeout(() => reject(timeoutError()), stallTimeout()); }),
    ]);
  } catch (error) { void reader.cancel(); throw error; }
  finally { if (timer) clearTimeout(timer); }
}

export function decodeZstdLimited(compressed: Uint8Array, maxBytes = MAX_DECOMPRESSED_BYTES): Buffer {
  try { return zstdDecompressSync(compressed, { maxOutputLength: maxBytes }); }
  catch { throw new AppError("sophon_manifest_too_large", "Sophon 清单解压结果超过大小限制", 502); }
}
