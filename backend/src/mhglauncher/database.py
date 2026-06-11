from __future__ import annotations

from collections.abc import AsyncIterator, Iterable
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import aiosqlite

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS account (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  aid TEXT NOT NULL, mid TEXT NOT NULL, nickname TEXT NOT NULL,
  credential_ref TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS roles (
  uid TEXT PRIMARY KEY, nickname TEXT NOT NULL, region TEXT NOT NULL,
  level INTEGER NOT NULL, selected INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS game_state (
  id INTEGER PRIMARY KEY CHECK (id = 1), install_path TEXT NOT NULL,
  version TEXT NOT NULL, status TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS wishes (
  id TEXT PRIMARY KEY, uid TEXT NOT NULL, gacha_type TEXT NOT NULL,
  item_id TEXT NOT NULL, name TEXT NOT NULL, item_type TEXT NOT NULL,
  rank INTEGER NOT NULL, time TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS wishes_uid_type ON wishes(uid, gacha_type, time DESC);
CREATE TABLE IF NOT EXISTS notes (
  uid TEXT PRIMARY KEY, payload TEXT NOT NULL, refreshed_at TEXT NOT NULL
);
"""


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path

    async def initialize(self) -> None:
        async with aiosqlite.connect(self.path) as connection:
            await connection.executescript(SCHEMA)
            await connection.commit()

    @asynccontextmanager
    async def connect(self) -> AsyncIterator[aiosqlite.Connection]:
        connection = await aiosqlite.connect(self.path)
        connection.row_factory = aiosqlite.Row
        try:
            await connection.execute("PRAGMA foreign_keys=ON")
            yield connection
            await connection.commit()
        finally:
            await connection.close()

    async def fetch_one(self, sql: str, values: Iterable[Any] = ()) -> aiosqlite.Row | None:
        async with self.connect() as connection:
            cursor = await connection.execute(sql, tuple(values))
            return await cursor.fetchone()

    async def fetch_all(self, sql: str, values: Iterable[Any] = ()) -> list[aiosqlite.Row]:
        async with self.connect() as connection:
            cursor = await connection.execute(sql, tuple(values))
            return list(await cursor.fetchall())

    async def execute(self, sql: str, values: Iterable[Any] = ()) -> None:
        async with self.connect() as connection:
            await connection.execute(sql, tuple(values))

    async def executemany(self, sql: str, values: Iterable[Iterable[Any]]) -> None:
        async with self.connect() as connection:
            await connection.executemany(sql, values)

