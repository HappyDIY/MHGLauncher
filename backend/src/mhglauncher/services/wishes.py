from __future__ import annotations

import builtins
from collections import defaultdict

from mhglauncher.database import Database
from mhglauncher.models import GameRole, WishRecord, WishStatistics
from mhglauncher.providers.base import Provider


class WishService:
    def __init__(self, database: Database, provider: Provider) -> None:
        self.database = database
        self.provider = provider

    async def sync(self, credential: str, role: GameRole) -> int:
        inserted = 0
        newest_ids = await self._newest_ids(role.uid)
        async for page in self.provider.iter_wishes(credential, role, newest_ids):
            before = await self._count(role.uid)
            await self.save(page)
            inserted += await self._count(role.uid) - before
        return inserted

    async def _newest_ids(self, uid: str) -> dict[str, str]:
        rows = await self.database.fetch_all(
            """
            SELECT gacha_type, MAX(id) AS id
            FROM wishes WHERE uid=? GROUP BY gacha_type
            """,
            (uid,),
        )
        return {str(row["gacha_type"]): str(row["id"]) for row in rows}

    async def save(self, records: list[WishRecord]) -> None:
        values = [
            (
                item.id,
                item.uid,
                item.gacha_type,
                item.item_id,
                item.name,
                item.item_type,
                item.rank,
                item.time.isoformat(),
            )
            for item in records
        ]
        if not values:
            return
        async with self.database.connect() as connection:
            await connection.executemany(
                """
                INSERT OR IGNORE INTO wishes(
                  id, uid, gacha_type, item_id, name, item_type, rank, time
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values,
            )

    async def clear(self) -> int:
        async with self.database.connect() as connection:
            cursor = await connection.execute("DELETE FROM wishes")
            return max(cursor.rowcount, 0)

    async def list(self, uid: str, gacha_type: str | None = None) -> list[WishRecord]:
        sql = "SELECT * FROM wishes WHERE uid=?"
        values: list[str] = [uid]
        if gacha_type:
            sql += " AND gacha_type=?"
            values.append(gacha_type)
        sql += " ORDER BY time DESC, id DESC"
        rows = await self.database.fetch_all(sql, values)
        return [WishRecord.model_validate(dict(row)) for row in rows]

    async def statistics(self, uid: str) -> builtins.list[WishStatistics]:
        records = await self.list(uid)
        groups: dict[str, builtins.list[WishRecord]] = defaultdict(builtins.list)
        for record in records:
            groups[record.gacha_type].append(record)
        results = []
        for gacha_type, items in sorted(groups.items()):
            pulls = 0
            for item in items:
                if item.rank == 5:
                    break
                pulls += 1
            results.append(
                WishStatistics(
                    uid=uid,
                    gacha_type=gacha_type,
                    total=len(items),
                    five_star_count=sum(item.rank == 5 for item in items),
                    pulls_since_five_star=pulls,
                )
            )
        return results

    async def _count(self, uid: str) -> int:
        row = await self.database.fetch_one(
            "SELECT COUNT(*) AS count FROM wishes WHERE uid=?",
            (uid,),
        )
        return int(row["count"]) if row else 0
