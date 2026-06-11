from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from mhglauncher.api import accounts, auth, game, notes, wishes
from mhglauncher.config import Settings
from mhglauncher.database import Database
from mhglauncher.errors import install_error_handlers
from mhglauncher.providers.base import Provider
from mhglauncher.providers.device import DeviceIdentity
from mhglauncher.providers.fixture import FixtureProvider
from mhglauncher.providers.live import LiveProvider
from mhglauncher.services.accounts import AccountService
from mhglauncher.services.games import GameService
from mhglauncher.services.notes import NoteService
from mhglauncher.services.wishes import WishService


def create_app(settings: Settings | None = None) -> FastAPI:
    effective = settings or Settings()
    effective.prepare()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        client = httpx.AsyncClient(
            timeout=effective.request_timeout,
            follow_redirects=True,
        )
        database = Database(effective.effective_database_path)
        await database.initialize()
        provider: Provider
        if effective.provider_mode == "fixture":
            fixture_dir = effective.fixture_dir or effective.data_dir / "fixtures"
            provider = FixtureProvider(fixture_dir)
        else:
            device = DeviceIdentity(effective.data_dir / "device.json")
            provider = LiveProvider(client, device)
        app.state.settings = effective
        app.state.database = database
        app.state.provider = provider
        app.state.accounts = AccountService(database, provider)
        app.state.wishes = WishService(database, provider)
        app.state.notes = NoteService(database, provider)
        app.state.games = GameService(database, provider, client, effective.data_dir)
        try:
            yield
        finally:
            await app.state.games.shutdown()
            await client.aclose()

    application = FastAPI(
        title="MHGLauncher Local API",
        version="1.0.0",
        lifespan=lifespan,
    )
    install_error_handlers(application)

    @application.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok", "version": "1.0.0"}

    for router in (auth.router, accounts.router, game.router, wishes.router, notes.router):
        application.include_router(router, prefix="/v1")
    return application
