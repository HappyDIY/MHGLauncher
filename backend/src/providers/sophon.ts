import { createHash } from "node:crypto";
import { zstdDecompressSync } from "node:zlib";
import { parse } from "protobufjs";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GameAsset, GameBuild, GamePatchAsset, SophonPatch } from "./provider";
import { normalizeBuild } from "./provider";

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

export class Sophon {
  private cached?: { time: number; version: string; build: GameBuild };

  async build(version = ""): Promise<GameBuild> {
    if (this.cached?.version === version && Date.now() - this.cached.time < 300_000) return this.cached.build;
    const branch = await this.branch();
    const build = (branch.diff_tags as string[] ?? []).includes(version) ? await this.patchBuild(branch, version) : await this.fullBuild(branch);
    this.cached = { time: Date.now(), version, build }; return build;
  }

  private async fullBuild(branch: JSONValue): Promise<GameBuild> {
    const query = new URLSearchParams({ branch: String(branch.branch), package_id: String(branch.package_id), password: String(branch.password), tag: String(branch.tag) });
    const data = await this.data(`https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getBuild?${query}`);
    const assets: GameAsset[] = [];
    for (const item of this.selected(data)) assets.push(...await this.assets(item));
    return normalizeBuild({ version: String(data.tag), assets });
  }

  private async patchBuild(branch: JSONValue, version: string): Promise<GameBuild> {
    const data = await this.data("https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getPatchBuild", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(branch) });
    const patch_assets: GamePatchAsset[] = [], deprecated_files: string[] = [];
    for (const item of this.selected(data)) {
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
    return normalizeBuild({ version: String(data.tag), kind: "version_diff", patch_assets, deprecated_files });
  }

  private async branch(): Promise<JSONValue> {
    const query = new URLSearchParams({ "game_ids[]": "1Z8W5NHUQb", launcher_id: "jGHBHlcOq1" });
    const data = await this.data(`https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGameBranches?${query}`);
    const value = (data.game_branches as JSONValue[] | undefined)?.[0]?.main as JSONValue | undefined;
    if (!value) throw new AppError("sophon_branch_missing", "未找到国服游戏分支", 502); return value;
  }

  private async assets(item: JSONValue): Promise<GameAsset[]> {
    const manifest = await this.manifest(item, "SophonManifest") as JSONValue;
    return (manifest.assets as JSONValue[] ?? []).map((asset) => ({ name: String(asset.asset_name), size: Number(asset.asset_size), md5: String(asset.asset_hash_md5),
      chunks: (asset.asset_chunks as JSONValue[] ?? []).map((chunk) => ({ name: String(chunk.chunk_name), decompressed_md5: String(chunk.chunk_decompressed_hash_md5), offset: Number(chunk.chunk_on_file_offset), size: Number(chunk.chunk_size), decompressed_size: Number(chunk.chunk_size_decompressed), url: this.url(item.chunk_download as JSONValue, String(chunk.chunk_name)) })) }));
  }

  private async manifest(item: JSONValue, type: "SophonManifest" | "PatchManifest"): Promise<unknown> {
    const info = item.manifest as JSONValue, response = await fetch(this.url(item.manifest_download as JSONValue, String(info.id)));
    if (!response.ok) throw new AppError("sophon_manifest_invalid", "Sophon 清单下载失败", 502);
    const compressed = Buffer.from(await response.arrayBuffer());
    if (type === "SophonManifest") { const expected = String(info.id).replace("manifest_", "").split("_", 1)[0]; if ((await xxhash()).h64Raw(compressed).toString(16).padStart(16, "0") !== expected?.toLowerCase()) throw new AppError("sophon_manifest_invalid", "Sophon 清单校验失败", 502); }
    const decoded = zstdDecompressSync(compressed); if (createHash("md5").update(decoded).digest("hex") !== String(info.checksum).toLowerCase()) throw new AppError("sophon_manifest_invalid", "Sophon 清单内容校验失败", 502);
    const model = root.lookupType(type); return model.toObject(model.decode(decoded), { longs: Number, defaults: true });
  }

  private selected(data: JSONValue): JSONValue[] { return (data.manifests as JSONValue[] ?? []).filter((item) => ["game", "zh-cn"].includes(String(item.matching_field))); }
  private url(download: JSONValue, name: string): string { const prefix = String(download.url_prefix).replace(/\/$/, ""), suffix = String(download.url_suffix ?? ""); return `${prefix}/${name}${suffix && !suffix.startsWith("?") ? "?" : ""}${suffix}`; }
  private async data(url: string, init?: RequestInit): Promise<JSONValue> { const response = await fetch(url, init), payload = await response.json() as JSONValue; if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "下载服务请求失败"), 502); return payload.data as JSONValue ?? {}; }
}
