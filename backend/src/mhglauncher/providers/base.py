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


class SophonChunk(BaseModel):
    name: str
    decompressed_md5: str
    offset: int
    size: int
    decompressed_size: int
    url: str


class GameAsset(BaseModel):
    name: str
    size: int
    md5: str
    chunks: list[SophonChunk]


class SophonPatch(BaseModel):
    id: str
    file_size: int
    start: int
    length: int
    original_name: str
    url: str


class GamePatchAsset(BaseModel):
    name: str
    size: int
    md5: str
    patch: SophonPatch


class GameBuild(BaseModel):
    version: str
    kind: str = "full"
    segments: list[PackageSegment] = []
    assets: list[GameAsset] = []
    patch_assets: list[GamePatchAsset] = []
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
        newest_ids: dict[str, str] | None = None,
    ) -> AsyncIterator[list[WishRecord]]: ...

    async def get_daily_note(
        self,
        credential: str,
        role: GameRole,
        xrpc_challenge: str = "",
    ) -> DailyNote: ...

    async def verify_note_challenge(
        self,
        credential: str,
        challenge: str,
        validate: str,
    ) -> str: ...
