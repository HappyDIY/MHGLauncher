from __future__ import annotations

import asyncio
import hashlib
from collections.abc import Callable
from pathlib import Path

import httpx

from mhglauncher.errors import AppError
from mhglauncher.providers.base import PackageSegment

Progress = Callable[[int], None]


class DownloadControl:
    def __init__(self) -> None:
        self.ready = asyncio.Event()
        self.ready.set()
        self.cancelled = False

    async def checkpoint(self) -> None:
        await self.ready.wait()
        if self.cancelled:
            raise asyncio.CancelledError

    def pause(self) -> None:
        self.ready.clear()

    def resume(self) -> None:
        self.ready.set()

    def cancel(self) -> None:
        self.cancelled = True
        self.ready.set()


class Downloader:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self.client = client

    async def download(
        self,
        segment: PackageSegment,
        destination: Path,
        control: DownloadControl,
        progress: Progress,
    ) -> Path:
        destination.parent.mkdir(parents=True, exist_ok=True)
        partial = destination.with_suffix(destination.suffix + ".part")
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > segment.size:
            partial.unlink()
            offset = 0
        headers = {"Range": f"bytes={offset}-"} if offset else {}
        async with self.client.stream("GET", segment.url, headers=headers) as response:
            response.raise_for_status()
            if offset and response.status_code != 206:
                partial.unlink(missing_ok=True)
                return await self.download(segment, destination, control, progress)
            with partial.open("ab") as stream:
                async for chunk in response.aiter_bytes(1024 * 256):
                    await control.checkpoint()
                    stream.write(chunk)
                    offset += len(chunk)
                    progress(len(chunk))
        if offset != segment.size:
            raise AppError("download_size_mismatch", f"{segment.filename} 下载大小不一致")
        if _md5(partial) != segment.md5.lower():
            partial.unlink(missing_ok=True)
            raise AppError("download_hash_mismatch", f"{segment.filename} 校验失败")
        partial.replace(destination)
        return destination


def _md5(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()

