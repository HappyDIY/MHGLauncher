from __future__ import annotations

from datetime import UTC, datetime

from mhglauncher.database import Database
from mhglauncher.models import Account, GameRole
from mhglauncher.providers.base import AccountIdentity, Provider


class AccountService:
    def __init__(self, database: Database, provider: Provider) -> None:
        self.database = database
        self.provider = provider

    async def save(
        self,
        identity: AccountIdentity,
        credential_ref: str,
    ) -> Account:
        now = datetime.now(UTC)
        await self.database.execute(
            """
            INSERT INTO account(id, aid, mid, nickname, credential_ref, updated_at)
            VALUES(1, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET aid=excluded.aid, mid=excluded.mid,
            nickname=excluded.nickname, credential_ref=excluded.credential_ref,
            updated_at=excluded.updated_at
            """,
            (identity.aid, identity.mid, identity.nickname, credential_ref, now.isoformat()),
        )
        return Account(
            aid=identity.aid,
            mid=identity.mid,
            nickname=identity.nickname,
            credential_ref=credential_ref,
            updated_at=now,
        )

    async def get(self) -> Account | None:
        row = await self.database.fetch_one("SELECT * FROM account WHERE id=1")
        return Account.model_validate(dict(row)) if row else None

    async def logout(self) -> None:
        async with self.database.connect() as connection:
            await connection.execute("DELETE FROM roles")
            await connection.execute("DELETE FROM account")

    async def sync_roles(self, credential: str) -> list[GameRole]:
        roles = await self.provider.get_roles(credential)
        values = [
            (role.uid, role.nickname, role.region, role.level, int(index == 0))
            for index, role in enumerate(roles)
        ]
        async with self.database.connect() as connection:
            await connection.execute("DELETE FROM roles")
            await connection.executemany(
                """
                INSERT INTO roles(uid, nickname, region, level, selected)
                VALUES(?, ?, ?, ?, ?)
                """,
                values,
            )
        return [
            role.model_copy(update={"selected": index == 0})
            for index, role in enumerate(roles)
        ]

    async def roles(self) -> list[GameRole]:
        rows = await self.database.fetch_all("SELECT * FROM roles ORDER BY selected DESC, uid")
        return [
            GameRole(
                uid=row["uid"],
                nickname=row["nickname"],
                region=row["region"],
                level=row["level"],
                selected=bool(row["selected"]),
            )
            for row in rows
        ]

    async def selected_role(self) -> GameRole | None:
        row = await self.database.fetch_one(
            "SELECT * FROM roles ORDER BY selected DESC, uid LIMIT 1"
        )
        if row is None:
            return None
        return GameRole(
            uid=row["uid"],
            nickname=row["nickname"],
            region=row["region"],
            level=row["level"],
            selected=bool(row["selected"]),
        )
