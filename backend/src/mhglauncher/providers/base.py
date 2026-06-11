from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Protocol

from pydantic import BaseModel

from mhglauncher.models import DailyNote, GameRole, QRSession, WishRecord


class PackageSegment(BaseModel):
    url: str
    md5: str
    size: int
    filename: str


class GameBuild(BaseModel):
    version: str
    segments: list[PackageSegment]
    deprecated_files: list[str] = []


class AccountIdentity(BaseModel):
    aid: str
    mid: str
    nickname: str
    credential: str


class Provider(Protocol):
    async def create_qr_session(self) -> QRSession: ...

    async def query_qr_session(
        self,
        session_id: str,
    ) -> tuple[QRSession, AccountIdentity | None]: ...

    async def get_roles(self, credential: str) -> list[GameRole]: ...

    async def get_build(self, installed_version: str = "") -> GameBuild: ...

    def iter_wishes(
        self,
        credential: str,
        role: GameRole,
        end_id: str = "0",
    ) -> AsyncIterator[list[WishRecord]]: ...

    async def get_daily_note(self, credential: str, role: GameRole) -> DailyNote: ...
