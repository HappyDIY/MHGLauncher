from __future__ import annotations

import asyncio
import hashlib
from collections.abc import Callable
from pathlib import Path, PurePosixPath

import httpx
import xxhash
import zstandard

from mhglauncher.errors import AppError
from mhglauncher.providers.base import GameAsset, SophonChunk
from mhglauncher.services.downloader import DownloadControl

Progress = Callable[[int], None]


class SophonInstaller:
    def __init__(self, client: httpx.AsyncClient, workers: int = 4) -> None:
        self.client = client
        self.semaphore = asyncio.Semaphore(workers)
        self.locks: dict[str, asyncio.Lock] = {}

    async def install(
        self,
        assets: list[GameAsset],
        staging: Path,
        cache: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> None:
        staging.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        for asset in assets:
            await control.checkpoint()
            target = _safe_target(staging, asset.name)
            if target.is_file() and await asyncio.to_thread(_md5, target) == asset.md5.lower():
                progress(sum(chunk.size for chunk in asset.chunks))
                continue
            paths = await asyncio.gather(
                *[
                    self._download(chunk, cache, control, progress)
                    for chunk in asset.chunks
                ]
            )
            await asyncio.to_thread(self._assemble, asset, paths, target)

    async def _download(
        self,
        chunk: SophonChunk,
        cache: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> Path:
        path = cache / chunk.name
        lock = self.locks.setdefault(chunk.name, asyncio.Lock())
        async with lock:
            if path.is_file() and await asyncio.to_thread(_chunk_valid, path, chunk.name):
                progress(chunk.size)
                return path
            async with self.semaphore:
                await control.checkpoint()
                await self._stream(chunk, path, control, progress)
            if not await asyncio.to_thread(_chunk_valid, path, chunk.name):
                path.unlink(missing_ok=True)
                raise AppError("sophon_chunk_invalid", f"{chunk.name} 分块校验失败")
            return path

    async def _stream(
        self,
        chunk: SophonChunk,
        path: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> None:
        partial = path.with_suffix(".part")
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > chunk.size:
            partial.unlink()
            offset = 0
        headers = {"Range": f"bytes={offset}-"} if offset else {}
        async with self.client.stream("GET", chunk.url, headers=headers) as response:
            response.raise_for_status()
            if offset and response.status_code != 206:
                partial.unlink(missing_ok=True)
                return await self._stream(chunk, path, control, progress)
            with partial.open("ab") as output:
                async for block in response.aiter_bytes(1024 * 256):
                    await control.checkpoint()
                    output.write(block)
                    offset += len(block)
                    progress(len(block))
        if offset != chunk.size:
            raise AppError("sophon_chunk_size_mismatch", f"{chunk.name} 分块大小不一致")
        partial.replace(path)

    @staticmethod
    def _assemble(asset: GameAsset, paths: list[Path], target: Path) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("wb") as output:
            output.truncate(asset.size)
        with target.open("r+b") as output:
            for chunk, path in zip(asset.chunks, paths, strict=True):
                decoded = zstandard.ZstdDecompressor().decompress(
                    path.read_bytes(),
                    max_output_size=chunk.decompressed_size,
                )
                digest = hashlib.md5(decoded, usedforsecurity=False).hexdigest()
                if digest != chunk.decompressed_md5.lower():
                    raise AppError("sophon_chunk_content_invalid", f"{chunk.name} 内容校验失败")
                output.seek(chunk.offset)
                output.write(decoded)
        if _md5(target) != asset.md5.lower():
            target.unlink(missing_ok=True)
            raise AppError("sophon_asset_invalid", f"{asset.name} 文件校验失败")


def _safe_target(root: Path, relative: str) -> Path:
    value = PurePosixPath(relative.replace("\\", "/"))
    if value.is_absolute() or ".." in value.parts:
        raise AppError("sophon_path_unsafe", f"资源路径不安全：{relative}")
    target = root.joinpath(*value.parts)
    if root.resolve() not in target.resolve().parents:
        raise AppError("sophon_path_unsafe", f"资源路径不安全：{relative}")
    return target


def _chunk_valid(path: Path, name: str) -> bool:
    expected = name.split("_", 1)[0].lower()
    return xxhash.xxh64_hexdigest(path.read_bytes()) == expected


def _md5(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()

