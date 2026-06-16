from __future__ import annotations

import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

from mhglauncher.database import Database
from mhglauncher.models import ChunkProgress, GameJob
from mhglauncher.providers.base import GameBuild


class ProgressTracker:
    def __init__(self, job: GameJob) -> None:
        self.job = job
        self._active: dict[str, dict[str, int]] = {}
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
        now = time.monotonic()
        elapsed = now - self._last_time
        if elapsed >= 0.5:
            delta = self.job.completed_bytes - self._last_bytes
            self.job.download_speed = int(delta / elapsed) if elapsed > 0 else 0
            self._last_time = now
            self._last_bytes = self.job.completed_bytes

    def on_chunk(self, name: str, offset: int, total: int) -> None:
        entry = self._active.setdefault(name, {"bytes": 0, "total": total})
        entry["bytes"] = offset
        entry["total"] = total
        if offset >= total:
            self._active.pop(name, None)
            self._completed.add(name)
            self.job.chunks_completed = len(self._completed)
        self.job.active_chunks = [
            ChunkProgress(name=k, bytes_done=v["bytes"], total=v["total"])
            for k, v in self._active.items()
        ]


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
