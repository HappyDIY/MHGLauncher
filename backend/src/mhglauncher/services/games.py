from __future__ import annotations

import asyncio
import shutil
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import httpx

from mhglauncher.database import Database
from mhglauncher.errors import AppError
from mhglauncher.models import GameJob, GameState, GameStatus, JobKind, JobStatus
from mhglauncher.providers.base import Provider
from mhglauncher.services.downloader import DownloadControl, Downloader
from mhglauncher.services.installer import Installer


class GameService:
    def __init__(
        self,
        database: Database,
        provider: Provider,
        client: httpx.AsyncClient,
        data_dir: Path,
    ) -> None:
        self.database = database
        self.provider = provider
        self.downloader = Downloader(client)
        self.installer = Installer()
        self.data_dir = data_dir
        self.jobs: dict[str, GameJob] = {}
        self.controls: dict[str, DownloadControl] = {}
        self.tasks: set[asyncio.Task[None]] = set()

    async def state(self) -> GameState:
        row = await self.database.fetch_one("SELECT * FROM game_state WHERE id=1")
        build = await self.provider.get_build(row["version"] if row else "")
        if row is None:
            return GameState(available_version=build.version)
        status = (
            GameStatus.READY
            if row["version"] == build.version
            else GameStatus.UPDATE_AVAILABLE
        )
        return GameState(
            install_path=row["install_path"],
            installed_version=row["version"],
            available_version=build.version,
            status=status,
        )

    async def start(self, kind: JobKind, install_path: Path) -> GameJob:
        if any(job.status in {JobStatus.QUEUED, JobStatus.RUNNING} for job in self.jobs.values()):
            raise AppError("game_job_busy", "已有游戏资源任务正在运行", 409)
        build = await self.provider.get_build()
        job = GameJob(
            id=str(uuid4()),
            kind=kind,
            status=JobStatus.QUEUED,
            total_bytes=sum(item.size for item in build.segments),
        )
        control = DownloadControl()
        self.jobs[job.id] = job
        self.controls[job.id] = control
        task = asyncio.create_task(self._run(job, control, install_path, build.version))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return job

    def get_job(self, job_id: str) -> GameJob:
        if job_id not in self.jobs:
            raise AppError("game_job_missing", "游戏资源任务不存在", 404)
        return self.jobs[job_id]

    def control(self, job_id: str, action: str) -> GameJob:
        job = self.get_job(job_id)
        control = self.controls[job_id]
        if action == "pause" and job.status is JobStatus.RUNNING:
            control.pause()
            job.status = JobStatus.PAUSED
        elif action == "resume" and job.status is JobStatus.PAUSED:
            control.resume()
            job.status = JobStatus.RUNNING
        elif action == "cancel":
            control.cancel()
        else:
            raise AppError("game_job_action_invalid", "任务操作与当前状态不匹配", 409)
        return job

    async def _run(
        self,
        job: GameJob,
        control: DownloadControl,
        install_path: Path,
        version: str,
    ) -> None:
        cache = self.data_dir / "downloads" / version
        staging = install_path.with_name(install_path.name + ".staging")
        try:
            job.status = JobStatus.RUNNING
            build = await self.provider.get_build()
            archives = []
            for segment in build.segments:
                archive = cache / segment.filename
                archives.append(
                    await self.downloader.download(
                        segment,
                        archive,
                        control,
                        lambda size: self._advance(job, size),
                    )
                )
            shutil.rmtree(staging, ignore_errors=True)
            if job.kind is JobKind.UPDATE and install_path.exists():
                shutil.copytree(install_path, staging)
            self.installer.extract(archives, staging)
            self.installer.verify(staging)
            (staging / ".mhg-version").write_text(version)
            self.installer.activate(staging, install_path)
            await self._save_state(install_path, version)
            job.status = JobStatus.COMPLETED
        except asyncio.CancelledError:
            job.status = JobStatus.CANCELLED
            job.message = "任务已取消"
        except Exception as error:
            job.status = JobStatus.FAILED
            job.message = str(error)
        finally:
            shutil.rmtree(staging, ignore_errors=True)

    @staticmethod
    def _advance(job: GameJob, size: int) -> None:
        job.completed_bytes += size

    async def _save_state(self, path: Path, version: str) -> None:
        now = datetime.now(UTC).isoformat()
        await self.database.execute(
            """
            INSERT INTO game_state(id, install_path, version, status, updated_at)
            VALUES(1, ?, ?, 'ready', ?)
            ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,
            version=excluded.version, status='ready', updated_at=excluded.updated_at
            """,
            (str(path), version, now),
        )

    async def shutdown(self) -> None:
        for control in self.controls.values():
            control.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
