from __future__ import annotations

from typing import cast

from fastapi import Request

from mhglauncher.services.accounts import AccountService
from mhglauncher.services.games import GameService
from mhglauncher.services.notes import NoteService
from mhglauncher.services.wish_tasks import WishTaskService
from mhglauncher.services.wishes import WishService


def accounts(request: Request) -> AccountService:
    return cast(AccountService, request.app.state.accounts)


def games(request: Request) -> GameService:
    return cast(GameService, request.app.state.games)


def wishes(request: Request) -> WishService:
    return cast(WishService, request.app.state.wishes)


def wish_tasks(request: Request) -> WishTaskService:
    return cast(WishTaskService, request.app.state.wish_tasks)


def notes(request: Request) -> NoteService:
    return cast(NoteService, request.app.state.notes)
