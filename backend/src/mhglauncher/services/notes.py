from __future__ import annotations

import json

from mhglauncher.database import Database
from mhglauncher.models import DailyNote, GameRole
from mhglauncher.providers.base import Provider


class NoteService:
    def __init__(self, database: Database, provider: Provider) -> None:
        self.database = database
        self.provider = provider

    async def refresh(self, credential: str, role: GameRole) -> DailyNote:
        note = await self.provider.get_daily_note(credential, role)
        await self.database.execute(
            """
            INSERT INTO notes(uid, payload, refreshed_at) VALUES(?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET payload=excluded.payload,
            refreshed_at=excluded.refreshed_at
            """,
            (role.uid, note.model_dump_json(), note.refreshed_at.isoformat()),
        )
        return note

    async def get(self, uid: str) -> DailyNote | None:
        row = await self.database.fetch_one("SELECT payload FROM notes WHERE uid=?", (uid,))
        if row is None:
            return None
        return DailyNote.model_validate(json.loads(row["payload"]))

