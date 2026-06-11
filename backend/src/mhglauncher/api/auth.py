from __future__ import annotations

from typing import Annotated, cast

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from mhglauncher.api.dependencies import accounts
from mhglauncher.models import QRSession
from mhglauncher.providers.base import AccountIdentity, Provider
from mhglauncher.security import require_token
from mhglauncher.services.accounts import AccountService

router = APIRouter(prefix="/auth", tags=["auth"], dependencies=[Depends(require_token)])


class QRResult(BaseModel):
    session: QRSession
    identity: AccountIdentity | None = None


class CompleteLogin(BaseModel):
    identity: AccountIdentity
    credential_ref: str


@router.post("/qr-sessions", response_model=QRSession)
async def create_qr(request: Request) -> QRSession:
    provider = cast(Provider, request.app.state.provider)
    return await provider.create_qr_session()


@router.get("/qr-sessions/{session_id}", response_model=QRResult)
async def query_qr(session_id: str, request: Request) -> QRResult:
    provider = cast(Provider, request.app.state.provider)
    session, identity = await provider.query_qr_session(session_id)
    return QRResult(session=session, identity=identity)


@router.post("/complete")
async def complete_login(
    body: CompleteLogin,
    service: Annotated[AccountService, Depends(accounts)],
) -> dict[str, object]:
    account = await service.save(body.identity, body.credential_ref)
    roles = await service.sync_roles(body.identity.credential)
    return {"account": account, "roles": roles}
