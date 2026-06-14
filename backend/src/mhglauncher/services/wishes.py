from __future__ import annotations

import asyncio
import builtins
from collections import defaultdict
from collections.abc import Callable
from typing import TYPE_CHECKING

from mhglauncher.database import Database
from mhglauncher.models import GameRole, WishBannerDetail, WishRecord, WishStatistics
from mhglauncher.providers.base import Provider
from mhglauncher.services.item_metadata import enrich_record, remote_icon_urls
from mhglauncher.services.wish_statistics import build_banner_detail

if TYPE_CHECKING:
    from mhglauncher.services.image_cache import ImageCacheService

WishLog = Callable[[str], None]


class WishService:
    def __init__(
        self,
        database: Database,
        provider: Provider,
        image_cache: ImageCacheService | None = None,
        port: int = 0,
    ) -> None:
        self.database = database
        self.provider = provider
        self._image_cache = image_cache
        self._port = port

    async def sync(
        self,
        credential: str,
        role: GameRole,
        log: WishLog | None = None,
    ) -> int:
        inserted = 0
        newest_ids = await self._newest_ids(role.uid)
        if log is not None:
            log(f"已读取 {len(newest_ids)} 个卡池的本地增量检查点")
        page_count = 0
        async for page in self.provider.iter_wishes(credential, role, newest_ids):
            before = await self._count(role.uid)
            await self.save(page)
            added = await self._count(role.uid) - before
            inserted += added
            page_count += 1
            if log is not None:
                log(f"第 {page_count} 页读取 {len(page)} 条记录，新增 {added} 条")
        if log is not None:
            log(f"米游社分页读取完成，共处理 {page_count} 页")
        return inserted

    async def _newest_ids(self, uid: str) -> dict[str, str]:
        rows = await self.database.fetch_all(
            """
            SELECT
              COALESCE(NULLIF(uigf_gacha_type, ''), gacha_type) AS gacha_type,
              MAX(id) AS id
            FROM wishes WHERE uid=?
            GROUP BY COALESCE(NULLIF(uigf_gacha_type, ''), gacha_type)
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
                item.uigf_gacha_type,
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
                INSERT INTO wishes(
                  id, uid, gacha_type, uigf_gacha_type,
                  item_id, name, item_type, rank, time
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  uigf_gacha_type=COALESCE(
                    NULLIF(excluded.uigf_gacha_type, ''),
                    wishes.uigf_gacha_type
                  ),
                  name=COALESCE(NULLIF(excluded.name, ''), wishes.name),
                  item_type=COALESCE(NULLIF(excluded.item_type, ''), wishes.item_type),
                  rank=CASE WHEN excluded.rank > 0 THEN excluded.rank ELSE wishes.rank END
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
        records = []
        item_ids: set[str] = set()
        for row in rows:
            data = dict(row)
            data["uigf_gacha_type"] = data["uigf_gacha_type"] or _uigf_type(str(data["gacha_type"]))
            record = WishRecord.model_validate(data)
            item_ids.add(record.item_id)
            records.append(enrich_record(record, self._image_cache, self._port))
        if item_ids and self._image_cache is not None:
            urls = remote_icon_urls(item_ids)
            if urls:
                asyncio.ensure_future(self._image_cache.ensure_all(urls))  # noqa: RUF006
        return records

    async def statistics(self, uid: str) -> builtins.list[WishStatistics]:
        records = await self.list(uid)
        groups: dict[str, builtins.list[WishRecord]] = defaultdict(builtins.list)
        for record in records:
            groups[record.uigf_gacha_type].append(record)
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

    async def banner_statistics(self, uid: str) -> builtins.list[WishBannerDetail]:
        sql = "SELECT * FROM wishes WHERE uid=? ORDER BY time ASC, id ASC"
        rows = await self.database.fetch_all(sql, (uid,))
        records = []
        for row in rows:
            data = dict(row)
            data["uigf_gacha_type"] = data["uigf_gacha_type"] or _uigf_type(str(data["gacha_type"]))
            records.append(WishRecord.model_validate(data))

        groups: dict[str, builtins.list[WishRecord]] = defaultdict(builtins.list)
        for record in records:
            groups[record.uigf_gacha_type].append(record)

        results = []
        for gacha_type, items in sorted(groups.items()):
            results.append(
                build_banner_detail(uid, gacha_type, items, self._image_cache, self._port)
            )
        return results


def _uigf_type(gacha_type: str) -> str:
    return "301" if gacha_type == "400" else gacha_type
