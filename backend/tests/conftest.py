from __future__ import annotations

from collections.abc import AsyncIterator
from pathlib import Path

import httpx
import pytest

from mhglauncher.app import create_app
from mhglauncher.config import Settings


@pytest.fixture
async def api_client(tmp_path: Path) -> AsyncIterator[httpx.AsyncClient]:
    fixture_dir = Path(__file__).parents[1] / "fixtures"
    settings = Settings(
        data_dir=tmp_path,
        database_path=tmp_path / "test.db",
        api_token="test-token",
        provider_mode="fixture",
        fixture_dir=fixture_dir,
    )
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers={"Authorization": "Bearer test-token"},
        ) as client:
            yield client

