from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from mhglauncher.api.dependencies import accounts, wishes
from mhglauncher.errors import AppError
from mhglauncher.models import WishBannerDetail, WishRecord, WishStatistics
from mhglauncher.security import require_token
from mhglauncher.services.accounts import AccountService
from mhglauncher.services.uigf import export_uigf, import_uigf
from mhglauncher.services.wishes import WishService

router = APIRouter(prefix="/wishes", tags=["wishes"], dependencies=[Depends(require_token)])


class SyncRequest(BaseModel):
    credential: str


@router.post("/sync")
async def sync(
    body: SyncRequest,
    account_service: Annotated[AccountService, Depends(accounts)],
    service: Annotated[WishService, Depends(wishes)],
) -> dict[str, int]:
    role = await account_service.selected_role()
    if role is None:
        raise AppError("role_missing", "尚未选择原神角色", 409)
    return {"inserted": await service.sync(body.credential, role)}


@router.get("", response_model=list[WishRecord])
async def list_records(
    uid: str,
    service: Annotated[WishService, Depends(wishes)],
    gacha_type: str | None = None,
) -> list[WishRecord]:
    return await service.list(uid, gacha_type)


@router.get("/statistics", response_model=list[WishStatistics])
async def statistics(
    uid: str,
    service: Annotated[WishService, Depends(wishes)],
) -> list[WishStatistics]:
    return await service.statistics(uid)


@router.get("/banner-statistics", response_model=list[WishBannerDetail])
async def banner_statistics(
    uid: str,
    service: Annotated[WishService, Depends(wishes)],
) -> list[WishBannerDetail]:
    return await service.banner_statistics(uid)


@router.post("/import")
async def import_records(
    payload: dict[str, Any],
    service: Annotated[WishService, Depends(wishes)],
) -> dict[str, int]:
    records = import_uigf(payload)
    await service.save(records)
    return {"imported": len(records)}


@router.delete("")
async def clear_records(
    service: Annotated[WishService, Depends(wishes)],
) -> dict[str, int]:
    return {"deleted": await service.clear()}


@router.get("/export")
async def export_records(
    uid: str,
    service: Annotated[WishService, Depends(wishes)],
) -> dict[str, Any]:
    return export_uigf(uid, await service.list(uid))
