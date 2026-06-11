from __future__ import annotations

import hashlib
from pathlib import Path

import httpx
import pytest

from mhglauncher.errors import AppError
from mhglauncher.providers.base import PackageSegment
from mhglauncher.services.downloader import DownloadControl, Downloader


async def test_resumes_partial_download(tmp_path: Path) -> None:
    content = b"0123456789"
    seen_range = ""

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal seen_range
        seen_range = request.headers.get("Range", "")
        start = int(seen_range.removeprefix("bytes=").removesuffix("-"))
        return httpx.Response(206, content=content[start:])

    partial = tmp_path / "game.zip.part"
    partial.write_bytes(content[:4])
    segment = PackageSegment(
        url="https://fixture.invalid/game.zip",
        md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
        size=len(content),
        filename="game.zip",
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await Downloader(client).download(
            segment,
            tmp_path / "game.zip",
            DownloadControl(),
            lambda _: None,
        )
    assert seen_range == "bytes=4-"
    assert result.read_bytes() == content


async def test_removes_corrupted_download(tmp_path: Path) -> None:
    segment = PackageSegment(
        url="https://fixture.invalid/game.zip",
        md5="0" * 32,
        size=3,
        filename="game.zip",
    )
    transport = httpx.MockTransport(lambda _: httpx.Response(200, content=b"bad"))
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(AppError, match="校验失败"):
            await Downloader(client).download(
                segment,
                tmp_path / "game.zip",
                DownloadControl(),
                lambda _: None,
            )
    assert not (tmp_path / "game.zip.part").exists()
