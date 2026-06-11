from __future__ import annotations

import hashlib
from pathlib import Path

import httpx
import xxhash
import zstandard

from mhglauncher.providers.base import GameAsset, SophonChunk
from mhglauncher.providers.sophon import SophonAPI
from mhglauncher.providers.sophon_proto import (
    AssetChunk,
    AssetProperty,
    SophonManifest,
)
from mhglauncher.services.downloader import DownloadControl
from mhglauncher.services.sophon_installer import SophonInstaller


async def test_sophon_installer_assembles_asset(tmp_path: Path) -> None:
    content = b"current genshin asset"
    compressed = zstandard.ZstdCompressor().compress(content)
    name = f"{xxhash.xxh64_hexdigest(compressed)}_fixture"
    chunk = SophonChunk(
        name=name,
        decompressed_md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        offset=0,
        size=len(compressed),
        decompressed_size=len(content),
        url="https://fixture.invalid/chunk",
    )
    asset = GameAsset(
        name="Genshin Impact Game/config.ini",
        size=len(content),
        md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        chunks=[chunk],
    )
    transport = httpx.MockTransport(lambda _: httpx.Response(200, content=compressed))
    async with httpx.AsyncClient(transport=transport) as client:
        await SophonInstaller(client).install(
            [asset],
            tmp_path / "staging",
            tmp_path / "cache",
            DownloadControl(),
            lambda _: None,
        )
    target = tmp_path / "staging/Genshin Impact Game/config.ini"
    assert target.read_bytes() == content


async def test_sophon_api_selects_game_and_chinese_manifests() -> None:
    manifest = SophonManifest(
        assets=[
            AssetProperty(
                asset_name="game.exe",
                asset_chunks=[
                    AssetChunk(
                        chunk_name="hash_chunk",
                        chunk_decompressed_hash_md5="md5",
                        chunk_on_file_offset=0,
                        chunk_size=10,
                        chunk_size_decompressed=20,
                    )
                ],
                asset_size=20,
                asset_hash_md5="asset-md5",
            )
        ]
    )
    raw_manifest = bytes(manifest)
    compressed = zstandard.ZstdCompressor().compress(raw_manifest)
    checksum = hashlib.md5(raw_manifest, usedforsecurity=False).hexdigest()
    manifest_id = f"manifest_{xxhash.xxh64_hexdigest(compressed)}_fixture"

    def handler(request: httpx.Request) -> httpx.Response:
        if "getGameBranches" in str(request.url):
            return httpx.Response(
                200,
                json={
                    "retcode": 0,
                    "data": {
                        "game_branches": [
                            {
                                "main": {
                                    "branch": "main",
                                    "package_id": "package",
                                    "password": "password",
                                    "tag": "6.6.0",
                                }
                            }
                        ]
                    },
                },
            )
        if "getBuild" in str(request.url):
            return httpx.Response(
                200,
                json={
                    "retcode": 0,
                    "data": {
                        "tag": "6.6.0",
                        "manifests": [
                            manifest_entry("game", manifest_id, checksum),
                            manifest_entry("en-us", manifest_id, checksum),
                        ],
                    },
                },
            )
        return httpx.Response(200, content=compressed)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        build = await SophonAPI(client).build()
    assert build.version == "6.6.0"
    assert len(build.assets) == 1
    assert build.assets[0].chunks[0].url.endswith("/hash_chunk")


def manifest_entry(field: str, manifest_id: str, checksum: str) -> dict[str, object]:
    return {
        "matching_field": field,
        "manifest": {"id": manifest_id, "checksum": checksum},
        "manifest_download": {"url_prefix": "https://fixture.invalid/manifests"},
        "chunk_download": {"url_prefix": "https://fixture.invalid/chunks"},
    }
