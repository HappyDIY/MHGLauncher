from __future__ import annotations

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MHG_", extra="ignore")

    data_dir: Path = Field(
        default_factory=lambda: Path.home() / "Library/Application Support/MHGLauncher"
    )
    database_path: Path | None = None
    api_token: str = ""
    provider_mode: str = "live"
    fixture_dir: Path | None = None
    request_timeout: float = 30.0
    download_workers: int = 4

    @property
    def effective_database_path(self) -> Path:
        return self.database_path or self.data_dir / "mhglauncher.db"

    def prepare(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.effective_database_path.parent.mkdir(parents=True, exist_ok=True)
