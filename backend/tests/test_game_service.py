from __future__ import annotations

import asyncio
import hashlib
import io
import zipfile
from collections.abc import AsyncIterator
from pathlib import Path

import httpx

from mhglauncher.database import Database
from mhglauncher.models import DailyNote, GameRole, JobKind, JobStatus, QRSession, WishRecord
from mhglauncher.providers.base import AccountIdentity, GameBuild, PackageSegment
from mhglauncher.services.games import GameService


class GameProvider:
    def __init__(self, build: GameBuild) -> None:
        self.build = build

    async def get_build(self, installed_version: str = "") -> GameBuild:
        del installed_version
        return self.build

    async def create_qr_session(self) -> QRSession:
        raise NotImplementedError

    async def query_qr_session(
        self,
        session_id: str,
    ) -> tuple[QRSession, AccountIdentity | None]:
        raise NotImplementedError

    async def get_roles(self, credential: str) -> list[GameRole]:
        raise NotImplementedError

    async def iter_wishes(
        self,
        credential: str,
        role: GameRole,
        end_id: str = "0",
    ) -> AsyncIterator[list[WishRecord]]:
        raise NotImplementedError
        yield []

    async def get_daily_note(self, credential: str, role: GameRole) -> DailyNote:
        raise NotImplementedError


async def test_install_job_downloads_and_activates(tmp_path: Path) -> None:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as package:
        package.writestr("Genshin Impact Game/config.ini", "game_version=5.8.0")
    content = buffer.getvalue()
    build = GameBuild(
        version="5.8.0",
        segments=[
            PackageSegment(
                url="https://fixture.invalid/game.zip",
                md5=hashlib.md5(content, usedforsecurity=False).hexdigest(),
                size=len(content),
                filename="game.zip",
            )
        ],
    )

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=content)

    database = Database(tmp_path / "game.db")
    await database.initialize()
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        service = GameService(database, GameProvider(build), client, tmp_path / "data")
        destination = tmp_path / "game"
        job = await service.start(JobKind.INSTALL, destination)
        for _ in range(100):
            if service.get_job(job.id).status not in {JobStatus.QUEUED, JobStatus.RUNNING}:
                break
            await asyncio.sleep(0.01)
        assert service.get_job(job.id).status is JobStatus.COMPLETED
        assert (destination / "Genshin Impact Game/config.ini").exists()
        state = await service.state()
        assert state.installed_version == "5.8.0"
        await service.shutdown()

