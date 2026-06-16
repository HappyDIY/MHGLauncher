from __future__ import annotations

import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from mhglauncher.database import Database
from mhglauncher.models import ChunkProgress, GameJob
from mhglauncher.providers.base import GameBuild

MAX_SLOTS = 4


class ProgressTracker:
    def __init__(self, job: GameJob) -> None:
        self.job = job
        self._slots: list[dict[str, Any] | None] = [None] * MAX_SLOTS
        self._name_to_slot: dict[str, int] = {}
        self._completed: set[str] = set()
        self._last_bytes = 0
        self._last_time = time.monotonic()

    @staticmethod
    def count_chunks(build: GameBuild) -> int:
        chunks = sum(len(a.chunks) for a in build.assets)
        patches = len({a.patch.id for a in build.patch_assets})
        return chunks + patches

    def bytes_callback(self) -> Callable[[int], None]:
        return self.on_bytes

    def chunk_callback(self) -> Callable[[str, int, int], None]:
        return self.on_chunk

    def on_bytes(self, size: int) -> None:
        self.job.completed_bytes += size
        self.job.last_update = datetime.now(UTC).isoformat()
        now = time.monotonic()
        elapsed = now - self._last_time
        if elapsed >= 0.5:
            delta = self.job.completed_bytes - self._last_bytes
            self.job.download_speed = int(delta / elapsed) if elapsed > 0 else 0
            self._last_time = now
            self._last_bytes = self.job.completed_bytes

    def on_chunk(self, name: str, offset: int, total: int) -> None:
        idx: int | None = self._name_to_slot.get(name)
        if idx is not None:
            slot = self._slots[idx]
            assert slot is not None
            slot["bytes"] = offset
            slot["total"] = total
        else:
            idx = self._find_slot()
            if idx is not None:
                old = self._slots[idx]
                if old is not None:
                    old_name = old["name"]
                    self._name_to_slot.pop(old_name, None)
                    if old["bytes"] >= old["total"]:
                        self._completed.add(old_name)
                self._slots[idx] = {"name": name, "bytes": offset, "total": total}
                self._name_to_slot[name] = idx
        if offset >= total:
            self._completed.add(name)
        self.job.chunks_completed = len(self._completed)
        self.job.active_chunks = [
            ChunkProgress(name=s["name"], bytes_done=s["bytes"], total=s["total"])
            for s in self._slots
            if s is not None
        ]

    def _find_slot(self) -> int | None:
        for i, s in enumerate(self._slots):
            if s is None:
                return i
        for i, s in enumerate(self._slots):
            if s is not None and s["bytes"] >= s["total"]:
                return i
        return None


async def save_state(database: Database, path: Path, version: str) -> None:
    now = datetime.now(UTC).isoformat()
    await database.execute(
        """
        INSERT INTO game_state(id, install_path, version, status, updated_at)
        VALUES(1, ?, ?, 'ready', ?)
        ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,
        version=excluded.version, status='ready', updated_at=excluded.updated_at
        """,
        (str(path), version, now),
    )
