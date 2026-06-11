from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class QRStatus(StrEnum):
    CREATED = "created"
    SCANNED = "scanned"
    CONFIRMED = "confirmed"
    EXPIRED = "expired"


class QRSession(BaseModel):
    id: str
    url: str
    status: QRStatus
    expires_at: datetime
    credential: str | None = None


class CredentialEnvelope(BaseModel):
    credential_ref: str
    credential: str = Field(min_length=1)


class Account(BaseModel):
    aid: str
    mid: str
    nickname: str
    credential_ref: str
    updated_at: datetime


class GameRole(BaseModel):
    uid: str
    nickname: str
    region: str
    level: int
    selected: bool = False


class WishRecord(BaseModel):
    id: str
    uid: str
    gacha_type: str
    item_id: str
    name: str
    item_type: str
    rank: int = Field(ge=3, le=5)
    time: datetime


class WishStatistics(BaseModel):
    uid: str
    gacha_type: str
    total: int
    five_star_count: int
    pulls_since_five_star: int


class DailyNote(BaseModel):
    uid: str
    current_resin: int
    max_resin: int
    finished_tasks: int
    total_tasks: int
    expeditions_finished: int
    expeditions_total: int
    current_home_coin: int
    max_home_coin: int
    weekly_boss_remaining: int
    transformer_ready: bool
    refreshed_at: datetime


class GameStatus(StrEnum):
    NOT_INSTALLED = "not_installed"
    READY = "ready"
    UPDATE_AVAILABLE = "update_available"
    BUSY = "busy"
    DAMAGED = "damaged"


class GameState(BaseModel):
    install_path: str = ""
    installed_version: str = ""
    available_version: str = ""
    status: GameStatus = GameStatus.NOT_INSTALLED


class JobKind(StrEnum):
    INSTALL = "install"
    UPDATE = "update"
    VERIFY = "verify"


class JobStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"


class GameJob(BaseModel):
    id: str
    kind: JobKind
    status: JobStatus
    completed_bytes: int = 0
    total_bytes: int = 0
    message: str = ""

