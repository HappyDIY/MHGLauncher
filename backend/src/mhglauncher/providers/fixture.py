from __future__ import annotations

import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from pathlib import Path

from mhglauncher.models import DailyNote, GameRole, QRSession, QRStatus, WishRecord
from mhglauncher.providers.base import AccountIdentity, GameBuild


class FixtureProvider:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.polls: dict[str, int] = {}

    async def create_qr_session(self) -> QRSession:
        session = QRSession(
            id="fixture-ticket",
            url="https://example.invalid/fixture-login",
            status=QRStatus.CREATED,
            expires_at=datetime.now(UTC) + timedelta(minutes=5),
        )
        self.polls[session.id] = 0
        return session

    async def query_qr_session(self, session_id: str) -> tuple[QRSession, AccountIdentity | None]:
        count = self.polls.get(session_id, 0) + 1
        self.polls[session_id] = count
        status = QRStatus.CONFIRMED if count >= 2 else QRStatus.SCANNED
        session = QRSession(
            id=session_id,
            url="https://example.invalid/fixture-login",
            status=status,
            expires_at=datetime.now(UTC) + timedelta(minutes=5),
        )
        identity = None
        if status is QRStatus.CONFIRMED:
            identity = AccountIdentity(
                aid="10001",
                mid="fixture-mid",
                nickname="测试旅行者",
                credential="stoken=fixture; mid=fixture-mid",
            )
        return session, identity

    async def get_roles(self, credential: str) -> list[GameRole]:
        del credential
        return [GameRole(uid="100000001", nickname="旅行者", region="cn_gf01", level=60)]

    async def get_build(self, installed_version: str = "") -> GameBuild:
        del installed_version
        return GameBuild.model_validate_json((self.root / "build.json").read_text())

    async def iter_wishes(
        self,
        credential: str,
        role: GameRole,
        end_id: str = "0",
    ) -> AsyncIterator[list[WishRecord]]:
        del credential, role, end_id
        payload = json.loads((self.root / "wishes.json").read_text())
        yield [WishRecord.model_validate(item) for item in payload]

    async def get_daily_note(self, credential: str, role: GameRole) -> DailyNote:
        del credential
        payload = json.loads((self.root / "note.json").read_text())
        return DailyNote.model_validate({"uid": role.uid, **payload})

