from __future__ import annotations

import asyncio
import hashlib
import os
import shutil
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path, PurePosixPath

import httpx
import xxhash

from mhglauncher.errors import AppError
from mhglauncher.providers.base import GamePatchAsset, SophonPatch
from mhglauncher.services.downloader import DownloadControl

Progress = Callable[[int], None]


class SophonPatchInstaller:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self.client = client
        self.semaphore = asyncio.Semaphore(4)

    async def install(
        self,
        assets: list[GamePatchAsset],
        staging: Path,
        cache: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> None:
        cache.mkdir(parents=True, exist_ok=True)
        patches = {asset.patch.id: asset.patch for asset in assets}
        downloaded = await asyncio.gather(
            *[
                self._download(patch, cache, control, progress)
                for patch in patches.values()
            ]
        )
        paths = dict(zip(patches, downloaded, strict=True))
        for asset in assets:
            await control.checkpoint()
            await asyncio.to_thread(self._apply, asset, paths[asset.patch.id], staging)

    async def _download(
        self,
        patch: SophonPatch,
        cache: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> Path:
        path = cache / patch.id
        if path.is_file() and await asyncio.to_thread(_valid_patch, path, patch):
            progress(patch.file_size)
            return path
        partial = path.with_suffix(".part")
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > patch.file_size:
            partial.unlink()
            offset = 0
        headers = {"Range": f"bytes={offset}-"} if offset else {}
        async with self.semaphore, self.client.stream(
            "GET",
            patch.url,
            headers=headers,
        ) as response:
            response.raise_for_status()
            if offset and response.status_code != 206:
                offset = 0
            elif offset:
                progress(offset)
            mode = "ab" if offset else "wb"
            with partial.open(mode) as output:
                async for block in response.aiter_bytes(1024 * 256):
                    await control.checkpoint()
                    output.write(block)
                    progress(len(block))
        if not await asyncio.to_thread(_valid_patch, partial, patch):
            partial.unlink(missing_ok=True)
            raise AppError("sophon_patch_invalid", f"{patch.id} 增量补丁校验失败")
        partial.replace(path)
        return path

    @staticmethod
    def _apply(asset: GamePatchAsset, patch_path: Path, staging: Path) -> None:
        target = _safe_target(staging, asset.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        segment = patch_path.with_name(f"{patch_path.name}.{asset.patch.start}.segment")
        with patch_path.open("rb") as source, segment.open("wb") as output:
            source.seek(asset.patch.start)
            output.write(source.read(asset.patch.length))
        try:
            if asset.patch.original_name:
                _apply_hpatch(target, segment, asset.size)
            else:
                segment.replace(target)
            if _md5(target) != asset.md5.lower():
                target.unlink(missing_ok=True)
                raise AppError("sophon_patch_result_invalid", f"{asset.name} 增量更新校验失败")
        finally:
            segment.unlink(missing_ok=True)


def _apply_hpatch(source: Path, patch: Path, target_size: int) -> None:
    if not source.is_file():
        raise AppError("sophon_patch_source_missing", f"{source.name} 缺少原始文件")
    tool = _hpatchz_path()
    output = source.with_suffix(source.suffix + ".patched")
    output.unlink(missing_ok=True)
    result = subprocess.run(
        [str(tool), str(source), str(patch), str(output)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not output.is_file() or output.stat().st_size != target_size:
        output.unlink(missing_ok=True)
        raise AppError("sophon_patch_apply_failed", f"{source.name} 增量补丁应用失败")
    output.replace(source)


def _hpatchz_path() -> Path:
    configured = os.environ.get("MHG_HPATCHZ")
    candidates = [
        Path(configured).expanduser() if configured else None,
        Path(sys.executable).with_name("hpatchz"),
        Path(shutil.which("hpatchz") or ""),
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate
    raise AppError("hpatchz_missing", "增量补丁工具不可用")


def _safe_target(root: Path, relative: str) -> Path:
    value = PurePosixPath(relative.replace("\\", "/"))
    if value.is_absolute() or ".." in value.parts:
        raise AppError("sophon_path_unsafe", f"资源路径不安全：{relative}")
    target = root.joinpath(*value.parts)
    if root.resolve() not in target.resolve().parents:
        raise AppError("sophon_path_unsafe", f"资源路径不安全：{relative}")
    return target


def _valid_patch(path: Path, patch: SophonPatch) -> bool:
    if path.stat().st_size != patch.file_size:
        return False
    digest = xxhash.xxh64()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest() == patch.id.split("_", 1)[0].lower()


def _md5(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()
