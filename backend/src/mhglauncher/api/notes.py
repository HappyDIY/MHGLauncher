from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from mhglauncher.api.dependencies import accounts, notes
from mhglauncher.errors import AppError
from mhglauncher.models import DailyNote
from mhglauncher.security import require_token
from mhglauncher.services.accounts import AccountService
from mhglauncher.services.notes import NoteService

router = APIRouter(prefix="/notes", tags=["notes"], dependencies=[Depends(require_token)])


class RefreshRequest(BaseModel):
    credential: str
    xrpc_challenge: str = ""


class VerificationRequest(BaseModel):
    credential: str
    challenge: str
    validation: str = Field(alias="validate")


class VerificationResponse(BaseModel):
    xrpc_challenge: str


@router.get("", response_model=DailyNote | None)
async def get_note(
    uid: str,
    service: Annotated[NoteService, Depends(notes)],
) -> DailyNote | None:
    return await service.get(uid)


@router.post("/refresh", response_model=DailyNote)
async def refresh(
    body: RefreshRequest,
    account_service: Annotated[AccountService, Depends(accounts)],
    service: Annotated[NoteService, Depends(notes)],
) -> DailyNote:
    role = await account_service.selected_role()
    if role is None:
        raise AppError("role_missing", "尚未选择原神角色", 409)
    return await service.refresh(body.credential, role, body.xrpc_challenge)


@router.post("/verification", response_model=VerificationResponse)
async def verify(
    body: VerificationRequest,
    service: Annotated[NoteService, Depends(notes)],
) -> VerificationResponse:
    challenge = await service.verify(
        body.credential,
        body.challenge,
        body.validation,
    )
    return VerificationResponse(xrpc_challenge=challenge)
