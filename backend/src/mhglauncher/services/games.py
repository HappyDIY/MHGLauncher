from __future__ import annotations

import asyncio
import json
import shutil
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import httpx

from mhglauncher.database import Database
from mhglauncher.errors import AppError
from mhglauncher.models import GameJob, GameState, GameStatus, JobKind, JobStatus
from mhglauncher.providers.base import GameBuild, Provider
from mhglauncher.services.downloader import DownloadControl, Downloader
from mhglauncher.services.game_build import download_size, remove_files, remove_retired_assets
from mhglauncher.services.game_detection import detect_game
from mhglauncher.services.installer import Installer
from mhglauncher.services.sophon_installer import SophonInstaller
from mhglauncher.services.sophon_patch_installer import SophonPatchInstaller


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
        self.sophon_installer = SophonInstaller(client)
        self.sophon_patch_installer = SophonPatchInstaller(client)
        self.data_dir = data_dir
        self.jobs: dict[str, GameJob] = {}
        self.controls: dict[str, DownloadControl] = {}
        self.tasks: set[asyncio.Task[None]] = set()

    async def state(self, install_path: Path | None = None) -> GameState:
        row = await self.database.fetch_one("SELECT * FROM game_state WHERE id=1")
        candidate = install_path or (Path(row["install_path"]) if row else None)
        detected = detect_game(candidate) if candidate else None
        installed_version = detected[1] if detected else ""
        build = await self.provider.get_build(installed_version)
        if detected is None:
            return GameState(
                install_path=str(candidate) if candidate else "",
                available_version=build.version,
            )
        detected_path, installed_version = detected
        await self._save_state(detected_path, installed_version)
        status = (
            GameStatus.READY
            if installed_version == build.version
            else GameStatus.UPDATE_AVAILABLE
        )
        return GameState(
            install_path=str(detected_path),
            installed_version=installed_version,
            available_version=build.version,
            status=status,
            update_kind="incremental" if build.patch_assets else "full",
            download_bytes=download_size(build),
        )

    async def start(self, kind: JobKind, install_path: Path) -> GameJob:
        if any(job.status in {JobStatus.QUEUED, JobStatus.RUNNING} for job in self.jobs.values()):
            raise AppError("game_job_busy", "已有游戏资源任务正在运行", 409)
        detected = detect_game(install_path)
        installed_version = detected[1] if detected else ""
        if kind is JobKind.UPDATE and detected is None:
            raise AppError("game_not_installed", "所选目录中未检测到可更新的原神客户端")
        if detected:
            install_path = detected[0]
        build = await self.provider.get_build(installed_version)
        job = GameJob(
            id=str(uuid4()),
            kind=kind,
            status=JobStatus.QUEUED,
            total_bytes=download_size(build),
        )
        control = DownloadControl()
        self.jobs[job.id] = job
        self.controls[job.id] = control
        task = asyncio.create_task(self._run(job, control, install_path, build))
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
        build: GameBuild,
    ) -> None:
        cache = self.data_dir / "downloads" / build.version
        staging = install_path.with_name(install_path.name + ".staging")
        try:
            job.status = JobStatus.RUNNING
            shutil.rmtree(staging, ignore_errors=True)
            if job.kind is JobKind.UPDATE and install_path.exists():
                shutil.copytree(install_path, staging)
                remove_retired_assets(staging, build)
            if build.patch_assets:
                await self.sophon_patch_installer.install(
                    build.patch_assets,
                    staging,
                    cache,
                    control,
                    lambda size: self._advance(job, size),
                )
                remove_files(staging, build.deprecated_files)
            elif build.assets:
                await self.sophon_installer.install(
                    build.assets,
                    staging,
                    cache,
                    control,
                    lambda size: self._advance(job, size),
                )
            else:
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
                self.installer.extract(archives, staging)
                self.installer.verify(staging)
            (staging / ".mhg-version").write_text(build.version)
            if build.assets:
                (staging / ".mhg-assets.json").write_text(
                    json.dumps([asset.name for asset in build.assets])
                )
            self.installer.activate(staging, install_path)
            await self._save_state(install_path, build.version)
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
