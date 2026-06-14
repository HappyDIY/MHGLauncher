from __future__ import annotations

import asyncio
from typing import Any
from uuid import uuid4

from mhglauncher.errors import AppError
from mhglauncher.models import WishTask, WishTaskLog, WishTaskStatus
from mhglauncher.services.accounts import AccountService
from mhglauncher.services.uigf import import_uigf
from mhglauncher.services.wishes import WishService


class WishTaskService:
    def __init__(self, accounts: AccountService, wishes: WishService) -> None:
        self.accounts = accounts
        self.wishes = wishes
        self.jobs: dict[str, WishTask] = {}
        self.tasks: set[asyncio.Task[None]] = set()

    def start_sync(self, credential: str) -> WishTask:
        job = self._create("sync")
        self._spawn(self._run_sync(job, credential))
        return job

    def start_import(self, payload: dict[str, Any]) -> WishTask:
        job = self._create("import_uigf")
        self._spawn(self._run_import(job, payload))
        return job

    def get(self, task_id: str) -> WishTask:
        job = self.jobs.get(task_id)
        if job is None:
            raise AppError("wish_task_missing", "祈愿任务不存在", 404)
        return job

    def _create(self, kind: str) -> WishTask:
        if any(
            job.status in {WishTaskStatus.QUEUED, WishTaskStatus.RUNNING}
            for job in self.jobs.values()
        ):
            raise AppError("wish_task_busy", "已有祈愿任务正在运行", 409)
        job = WishTask(id=str(uuid4()), kind=kind)
        self.jobs[job.id] = job
        self._append(job, "后端已创建任务")
        return job

    def _spawn(self, coroutine: Any) -> None:
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    async def _run_sync(self, job: WishTask, credential: str) -> None:
        try:
            job.status = WishTaskStatus.RUNNING
            self._append(job, "正在读取当前选择的游戏角色", progress=0.1, update_progress=True)
            role = await self.accounts.selected_role()
            if role is None:
                raise AppError("role_missing", "尚未选择原神角色", 409)
            self._append(job, f"已选择角色 UID {role.uid}", emphasized=True)
            self._append(job, "正在读取米游社祈愿分页", progress=None, update_progress=True)
            inserted = await self.wishes.sync(
                credential,
                role,
                lambda message: self._append(job, message),
            )
            self._complete(job, {"inserted": inserted}, f"同步完成，新增 {inserted} 条记录")
        except Exception as error:
            self._fail(job, error)

    async def _run_import(self, job: WishTask, payload: dict[str, Any]) -> None:
        try:
            job.status = WishTaskStatus.RUNNING
            self._append(job, "正在解析并校验 UIGF 数据", progress=None, update_progress=True)
            records = import_uigf(payload)
            self._append(
                job,
                f"已校验 {len(records)} 条 UIGF 记录",
                progress=0.5,
                update_progress=True,
            )
            self._append(job, "正在写入祈愿数据库")
            await self.wishes.save(records)
            self._complete(job, {"imported": len(records)}, f"成功导入 {len(records)} 条记录")
        except Exception as error:
            self._fail(job, error)

    def _complete(self, job: WishTask, result: dict[str, int], message: str) -> None:
        job.result = result
        job.status = WishTaskStatus.COMPLETED
        self._append(job, message, progress=1.0, emphasized=True, update_progress=True)

    def _fail(self, job: WishTask, error: Exception) -> None:
        message = error.message if isinstance(error, AppError) else str(error)
        job.error = message or "祈愿任务执行失败"
        job.status = WishTaskStatus.FAILED
        self._append(job, job.error, emphasized=True)

    @staticmethod
    def _append(
        job: WishTask,
        message: str,
        progress: float | None = None,
        emphasized: bool = False,
        update_progress: bool = False,
    ) -> None:
        if update_progress:
            job.progress = progress
        job.logs.append(
            WishTaskLog(
                sequence=len(job.logs) + 1,
                message=message,
                emphasized=emphasized,
            )
        )

    async def shutdown(self) -> None:
        for task in self.tasks:
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
