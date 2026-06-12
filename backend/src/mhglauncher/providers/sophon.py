from __future__ import annotations

import hashlib
from typing import Any
from urllib.parse import urlencode

import httpx
import xxhash
import zstandard

from mhglauncher.errors import AppError
from mhglauncher.providers.base import (
    GameAsset,
    GameBuild,
    GamePatchAsset,
    SophonChunk,
    SophonPatch,
)
from mhglauncher.providers.sophon_proto import PatchManifest, SophonManifest


class SophonAPI:
    GAME_ID = "1Z8W5NHUQb"
    LAUNCHER_ID = "jGHBHlcOq1"
    BRANCHES = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGameBranches"
    BUILD = "https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getBuild"
    PATCH_BUILD = "https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getPatchBuild"

    def __init__(self, client: httpx.AsyncClient) -> None:
        self.client = client

    async def build(self, installed_version: str = "") -> GameBuild:
        branch = await self._branch()
        if installed_version in branch.get("diff_tags", []):
            return await self._patch_build(branch, installed_version)
        query = urlencode(
            {
                "branch": branch["branch"],
                "package_id": branch["package_id"],
                "password": branch["password"],
                "tag": branch["tag"],
            }
        )
        data = self._data(await self.client.get(f"{self.BUILD}?{query}"))
        manifests = [
            item
            for item in data["manifests"]
            if item.get("matching_field") in {"game", "zh-cn"}
        ]
        assets = []
        for item in manifests:
            assets.extend(await self._assets(item))
        return GameBuild(version=str(data["tag"]), assets=assets)

    async def _patch_build(
        self,
        branch: dict[str, Any],
        installed_version: str,
    ) -> GameBuild:
        data = self._data(await self.client.post(self.PATCH_BUILD, json=branch))
        manifests = self._selected_manifests(data)
        assets: list[GamePatchAsset] = []
        deprecated: list[str] = []
        for item in manifests:
            manifest = await self._patch_manifest(item)
            diff_download = item["diff_download"]
            for file in manifest.file_datas:
                entry = next(
                    (value for value in file.patches_entries if value.key == installed_version),
                    None,
                )
                if entry is None:
                    continue
                info = entry.patch_info
                assets.append(
                    GamePatchAsset(
                        name=file.file_name,
                        size=file.file_size,
                        md5=file.file_hash,
                        patch=SophonPatch(
                            id=info.id,
                            file_size=info.patch_file_size,
                            start=info.patch_start_offset,
                            length=info.patch_length,
                            original_name=info.original_file_name,
                            url=self._url(diff_download, info.id),
                        ),
                    )
                )
            deprecated.extend(self._deprecated(manifest, installed_version))
        return GameBuild(
            version=str(data["tag"]),
            patch_assets=assets,
            deprecated_files=deprecated,
        )

    async def _branch(self) -> dict[str, Any]:
        query = urlencode(
            {"game_ids[]": self.GAME_ID, "launcher_id": self.LAUNCHER_ID},
            doseq=True,
        )
        data = self._data(await self.client.get(f"{self.BRANCHES}?{query}"))
        branches = data.get("game_branches", [])
        if not branches:
            raise AppError("sophon_branch_missing", "未找到国服游戏分支", 502)
        branch: dict[str, Any] = branches[0]["main"]
        return branch

    async def _assets(self, item: dict[str, Any]) -> list[GameAsset]:
        manifest_info = item["manifest"]
        download = item["manifest_download"]
        url = self._url(download, str(manifest_info["id"]))
        compressed = (await self.client.get(url)).content
        manifest_id = str(manifest_info["id"])
        expected_chunk = manifest_id.removeprefix("manifest_").split("_", 1)[0]
        if xxhash.xxh64_hexdigest(compressed) != expected_chunk.lower():
            raise AppError("sophon_manifest_invalid", "Sophon 清单校验失败", 502)
        decoded = zstandard.ZstdDecompressor().decompress(compressed)
        checksum = hashlib.md5(decoded, usedforsecurity=False).hexdigest()
        if checksum != str(manifest_info["checksum"]).lower():
            raise AppError("sophon_manifest_invalid", "Sophon 清单内容校验失败", 502)
        manifest = SophonManifest().parse(decoded)
        chunk_download = item["chunk_download"]
        return [
            GameAsset(
                name=asset.asset_name,
                size=asset.asset_size,
                md5=asset.asset_hash_md5,
                chunks=[
                    SophonChunk(
                        name=chunk.chunk_name,
                        decompressed_md5=chunk.chunk_decompressed_hash_md5,
                        offset=chunk.chunk_on_file_offset,
                        size=chunk.chunk_size,
                        decompressed_size=chunk.chunk_size_decompressed,
                        url=self._url(chunk_download, chunk.chunk_name),
                    )
                    for chunk in asset.asset_chunks
                ],
            )
            for asset in manifest.assets
        ]

    async def _patch_manifest(self, item: dict[str, Any]) -> PatchManifest:
        decoded = await self._manifest_bytes(item)
        return PatchManifest().parse(decoded)

    async def _manifest_bytes(self, item: dict[str, Any]) -> bytes:
        manifest_info = item["manifest"]
        url = self._url(item["manifest_download"], str(manifest_info["id"]))
        compressed = (await self.client.get(url)).content
        decoded = zstandard.ZstdDecompressor().decompress(compressed)
        checksum = hashlib.md5(decoded, usedforsecurity=False).hexdigest()
        if checksum != str(manifest_info["checksum"]).lower():
            raise AppError("sophon_manifest_invalid", "Sophon 清单内容校验失败", 502)
        return decoded

    @staticmethod
    def _selected_manifests(data: dict[str, Any]) -> list[dict[str, Any]]:
        return [
            item
            for item in data["manifests"]
            if item.get("matching_field") in {"game", "zh-cn"}
        ]

    @staticmethod
    def _deprecated(manifest: PatchManifest, version: str) -> list[str]:
        for entry in manifest.delete_files_entries:
            if entry.key == version:
                return [item.name for item in entry.delete_files.infos]
        return []

    @staticmethod
    def _url(download: dict[str, Any], name: str) -> str:
        prefix = str(download["url_prefix"]).rstrip("/")
        suffix = str(download.get("url_suffix", ""))
        separator = "?" if suffix and not suffix.startswith("?") else ""
        return f"{prefix}/{name}{separator}{suffix}"

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError("mihoyo_error", str(payload.get("message", "下载服务请求失败")), 502)
        data: dict[str, Any] = payload.get("data") or {}
        return data
