from __future__ import annotations

import hashlib
from pathlib import Path

import httpx
import xxhash
import zstandard

from mhglauncher.providers.base import GamePatchAsset, SophonPatch
from mhglauncher.providers.sophon import SophonAPI
from mhglauncher.providers.sophon_proto import (
    DeleteFiles,
    DeleteFilesEntry,
    FileInfo,
    PatchesEntry,
    PatchFileData,
    PatchInfo,
    PatchManifest,
)
from mhglauncher.services.downloader import DownloadControl
from mhglauncher.services.game_build import download_size
from mhglauncher.services.sophon_patch_installer import SophonPatchInstaller


async def test_sophon_api_selects_incremental_patch_for_installed_version() -> None:
    manifest = PatchManifest(
        file_datas=[
            PatchFileData(
                file_name="config.ini",
                file_size=12,
                file_hash="target-md5",
                patches_entries=[
                    PatchesEntry(
                        key="6.5.0",
                        patch_info=PatchInfo(
                            id="patch-id",
                            patch_file_size=20,
                            patch_start_offset=3,
                            patch_length=9,
                            original_file_name="config.ini",
                        ),
                    )
                ],
            )
        ],
        delete_files_entries=[
            DeleteFilesEntry(
                key="6.5.0",
                delete_files=DeleteFiles(infos=[FileInfo(name="retired.bin")]),
            )
        ],
    )
    raw = bytes(manifest)
    compressed = zstandard.ZstdCompressor().compress(raw)
    checksum = hashlib.md5(raw, usedforsecurity=False).hexdigest()
    requested_patch = False

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal requested_patch
        if "getGameBranches" in str(request.url):
            return httpx.Response(200, json=_branch_response())
        if "getPatchBuild" in str(request.url):
            requested_patch = True
            return httpx.Response(200, json=_patch_response(checksum))
        return httpx.Response(200, content=compressed)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        build = await SophonAPI(client).build("6.5.0")
    assert requested_patch
    assert build.patch_assets[0].patch.id == "patch-id"
    assert build.deprecated_files == ["retired.bin"]
    assert download_size(build) == 20


async def test_sophon_patch_installer_applies_direct_replacement(tmp_path: Path) -> None:
    content = b"replacement"
    patch_id = f"{xxhash.xxh64_hexdigest(content)}_fixture"
    asset = GamePatchAsset(
        name="config.ini",
        size=len(content),
        md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        patch=SophonPatch(
            id=patch_id,
            file_size=len(content),
            start=0,
            length=len(content),
            original_name="",
            url="https://fixture.invalid/patch",
        ),
    )
    transport = httpx.MockTransport(lambda _: httpx.Response(200, content=content))
    async with httpx.AsyncClient(transport=transport) as client:
        await SophonPatchInstaller(client).install(
            [asset],
            tmp_path / "staging",
            tmp_path / "cache",
            DownloadControl(),
            lambda _: None,
        )
    assert (tmp_path / "staging/config.ini").read_bytes() == content


async def test_sophon_patch_download_resumes_partial_file(tmp_path: Path) -> None:
    content = b"resumable replacement"
    patch_id = f"{xxhash.xxh64_hexdigest(content)}_fixture"
    asset = GamePatchAsset(
        name="config.ini",
        size=len(content),
        md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        patch=SophonPatch(
            id=patch_id,
            file_size=len(content),
            start=0,
            length=len(content),
            original_name="",
            url="https://fixture.invalid/patch",
        ),
    )
    cache = tmp_path / "cache"
    cache.mkdir()
    (cache / f"{patch_id}.part").write_bytes(content[:5])

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Range"] == "bytes=5-"
        return httpx.Response(206, content=content[5:])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await SophonPatchInstaller(client).install(
            [asset],
            tmp_path / "staging",
            cache,
            DownloadControl(),
            lambda _: None,
        )
    assert (tmp_path / "staging/config.ini").read_bytes() == content


def _branch_response() -> dict[str, object]:
    return {
        "retcode": 0,
        "data": {
            "game_branches": [
                {
                    "main": {
                        "branch": "main",
                        "package_id": "package",
                        "password": "password",
                        "tag": "6.6.0",
                        "diff_tags": ["6.5.0"],
                    }
                }
            ]
        },
    }


def _patch_response(checksum: str) -> dict[str, object]:
    return {
        "retcode": 0,
        "data": {
            "tag": "6.6.0",
            "manifests": [
                {
                    "matching_field": "game",
                    "manifest": {"id": "patch-manifest", "checksum": checksum},
                    "manifest_download": {"url_prefix": "https://fixture.invalid/manifests"},
                    "diff_download": {"url_prefix": "https://fixture.invalid/diffs"},
                }
            ],
        },
    }
