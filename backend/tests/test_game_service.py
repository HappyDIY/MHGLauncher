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
from mhglauncher.providers.base import (
    AccountIdentity,
    GameAsset,
    GameBuild,
    PackageSegment,
    SophonChunk,
)
from mhglauncher.services.games import GameService


class GameProvider:
    def __init__(self, build: GameBuild) -> None:
        self.build = build
        self.installed_versions: list[str] = []

    async def get_build(self, installed_version: str = "") -> GameBuild:
        self.installed_versions.append(installed_version)
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
        newest_ids: dict[str, str] | None = None,
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


async def test_existing_game_is_detected_and_update_uses_local_version(
    tmp_path: Path,
) -> None:
    game = tmp_path / "Genshin Impact Game"
    game.mkdir()
    (game / "YuanShen.exe").write_bytes(b"")
    (game / "config.ini").write_text(
        "[General]\ngame_version=6.5.0\n",
        encoding="utf-8",
    )
    provider = GameProvider(GameBuild(version="6.6.0"))
    database = Database(tmp_path / "game.db")
    await database.initialize()
    async with httpx.AsyncClient() as client:
        service = GameService(database, provider, client, tmp_path / "data")
        state = await service.state(game)
        assert state.install_path == str(game)
        assert state.installed_version == "6.5.0"
        assert state.status.value == "update_available"
        assert state.update_kind == "full"

        await service.start(JobKind.UPDATE, game)
        assert provider.installed_versions[-1] == "6.5.0"
        await service.shutdown()


async def test_same_version_changed_asset_triggers_hotfix(tmp_path: Path) -> None:
    game = tmp_path / "game"
    game.mkdir()
    (game / "YuanShen.exe").write_bytes(b"")
    (game / "config.ini").write_text("[General]\ngame_version=6.6.0\n")
    build = GameBuild(
        version="6.6.0",
        assets=[
            GameAsset(
                name="hotfix.bin",
                size=3,
                md5="22af645d1859cb5ca6da0c484f1f37ea",
                chunks=[
                    SophonChunk(
                        name="chunk",
                        decompressed_md5="22af645d1859cb5ca6da0c484f1f37ea",
                        offset=0,
                        size=3,
                        decompressed_size=3,
                        url="https://fixture.invalid/chunk",
                    )
                ],
            )
        ],
    )
    database = Database(tmp_path / "game.db")
    await database.initialize()
    async with httpx.AsyncClient() as client:
        service = GameService(database, GameProvider(build), client, tmp_path / "data")
        state = await service.state(game)
        assert state.status.value == "update_available"
        assert state.update_kind == "hotfix"
        assert state.download_bytes == 3
        await service.shutdown()
