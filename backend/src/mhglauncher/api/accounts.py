from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from mhglauncher.api.dependencies import accounts
from mhglauncher.models import Account, GameRole
from mhglauncher.security import require_token
from mhglauncher.services.accounts import AccountService

router = APIRouter(tags=["account"], dependencies=[Depends(require_token)])


class CredentialRequest(BaseModel):
    credential: str


@router.get("/account", response_model=Account | None)
async def get_account(
    service: Annotated[AccountService, Depends(accounts)],
) -> Account | None:
    return await service.get()


@router.delete("/account", status_code=204)
async def logout(service: Annotated[AccountService, Depends(accounts)]) -> None:
    await service.logout()


@router.get("/roles", response_model=list[GameRole])
async def list_roles(
    service: Annotated[AccountService, Depends(accounts)],
) -> list[GameRole]:
    return await service.roles()


@router.post("/roles/sync", response_model=list[GameRole])
async def sync_roles(
    body: CredentialRequest,
    service: Annotated[AccountService, Depends(accounts)],
) -> list[GameRole]:
    return await service.sync_roles(body.credential)

