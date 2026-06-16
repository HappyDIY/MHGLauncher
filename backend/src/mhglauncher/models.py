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
    uigf_gacha_type: str = ""
    item_id: str
    name: str
    item_type: str
    rank: int = Field(ge=0, le=5)
    time: datetime
    icon_url: str | None = None


class WishStatistics(BaseModel):
    uid: str
    gacha_type: str
    total: int
    five_star_count: int
    pulls_since_five_star: int


class WishBannerItem(BaseModel):
    name: str
    item_id: str
    item_type: str
    rank: int
    icon_url: str | None = None
    pull_number: int
    pity: int
    time: datetime


class WishBannerDetail(BaseModel):
    uid: str
    gacha_type: str
    total: int
    time_from: datetime | None = None
    time_to: datetime | None = None
    five_star_count: int = 0
    four_star_count: int = 0
    three_star_count: int = 0
    five_star_percent: float = 0.0
    four_star_percent: float = 0.0
    three_star_percent: float = 0.0
    max_pity: int = 0
    min_pity: int = 0
    average_pity: float = 0.0
    last_pity: int = 0
    last_purple_pity: int = 0
    guarantee_threshold: int = 90
    five_star_items: list[WishBannerItem] = []
    four_star_items: list[WishBannerItem] = []


class WishTaskStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class WishTaskLog(BaseModel):
    sequence: int
    message: str
    emphasized: bool = False


class WishTask(BaseModel):
    id: str
    kind: str
    status: WishTaskStatus = WishTaskStatus.QUEUED
    progress: float | None = 0.0
    logs: list[WishTaskLog] = Field(default_factory=list)
    result: dict[str, int] | None = None
    error: str = ""


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
    update_kind: str = ""
    download_bytes: int = 0


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


class ChunkProgress(BaseModel):
    name: str
    bytes_done: int = 0
    total: int = 0


class GameJob(BaseModel):
    id: str
    kind: JobKind
    status: JobStatus
    completed_bytes: int = 0
    total_bytes: int = 0
    message: str = ""
    download_speed: int = 0
    chunks_completed: int = 0
    chunks_total: int = 0
    active_chunks: list[ChunkProgress] = []
