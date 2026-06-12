from __future__ import annotations

from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from mhglauncher.api.dependencies import games
from mhglauncher.errors import AppError
from mhglauncher.models import GameJob, GameState, JobKind
from mhglauncher.security import require_token
from mhglauncher.services.games import GameService

router = APIRouter(prefix="/game", tags=["game"], dependencies=[Depends(require_token)])


class StartJob(BaseModel):
    kind: JobKind
    install_path: str


class ControlJob(BaseModel):
    action: Literal["pause", "resume", "cancel"]


@router.get("/status", response_model=GameState)
async def status(service: Annotated[GameService, Depends(games)]) -> GameState:
    return await service.state()


@router.get("/status/path", response_model=GameState)
async def status_for_path(
    service: Annotated[GameService, Depends(games)],
    install_path: Annotated[str, Query(min_length=1)],
) -> GameState:
    return await service.state(Path(install_path).expanduser())


@router.post("/jobs", response_model=GameJob, status_code=202)
async def start_job(
    body: StartJob,
    service: Annotated[GameService, Depends(games)],
) -> GameJob:
    return await service.start(body.kind, Path(body.install_path).expanduser())


@router.get("/jobs/{job_id}", response_model=GameJob)
async def get_job(
    job_id: str,
    service: Annotated[GameService, Depends(games)],
) -> GameJob:
    return service.get_job(job_id)


@router.post("/jobs/{job_id}/control", response_model=GameJob)
async def control_job(
    job_id: str,
    body: ControlJob,
    service: Annotated[GameService, Depends(games)],
) -> GameJob:
    return service.control(job_id, body.action)


@router.post("/launch")
async def launch() -> None:
    raise AppError("launch_not_implemented", "游戏启动功能尚未实现", 501)
