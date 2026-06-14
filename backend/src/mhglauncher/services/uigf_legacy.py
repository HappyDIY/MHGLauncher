from __future__ import annotations

import builtins
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from mhglauncher.errors import AppError
from mhglauncher.models import WishRecord
from mhglauncher.services.item_metadata import enrich_record


class LegacyInfo(BaseModel):
    model_config = ConfigDict(extra="ignore")

    uid: str
    uigf_version: str

    @field_validator("uid", mode="before")
    @classmethod
    def stringify_uid(cls, value: Any) -> Any:
        return str(value) if isinstance(value, int) else value


class LegacyItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: str = Field(min_length=1, max_length=19, pattern=r"^[0-9]+$")
    uigf_gacha_type: str
    gacha_type: str
    item_id: str
    time: str
    name: str = ""
    item_type: str = ""
    rank_type: str | None = None

    @field_validator(
        "id",
        "uigf_gacha_type",
        "gacha_type",
        "item_id",
        "rank_type",
        mode="before",
    )
    @classmethod
    def stringify_numbers(cls, value: Any) -> Any:
        return str(value) if isinstance(value, int) else value


class LegacyFile(BaseModel):
    model_config = ConfigDict(extra="ignore")

    info: LegacyInfo
    list: builtins.list[LegacyItem] = Field(default_factory=builtins.list)


def import_legacy_uigf(payload: dict[str, Any]) -> list[WishRecord]:
    try:
        document = LegacyFile.model_validate(payload)
        if not document.info.uigf_version.startswith(("v2.", "v3.")):
            raise ValueError("unsupported legacy UIGF version")
        records = [_record(document.info.uid, item) for item in document.list]
    except (ValidationError, ValueError) as error:
        raise AppError("uigf_invalid", "旧版 UIGF 文件格式无效") from error
    if not records:
        raise AppError("uigf_empty", "UIGF 文件不包含原神祈愿记录")
    return records


def _record(uid: str, item: LegacyItem) -> WishRecord:
    try:
        return enrich_record(
            WishRecord(
                id=item.id,
                uid=uid,
                gacha_type=item.gacha_type,
                uigf_gacha_type=item.uigf_gacha_type,
                item_id=item.item_id,
                name=item.name,
                item_type=item.item_type,
                rank=int(item.rank_type or 0),
                time=datetime.strptime(item.time, "%Y-%m-%d %H:%M:%S"),
            )
        )
    except (TypeError, ValueError) as error:
        raise AppError("uigf_item_invalid", "UIGF 记录字段无效") from error
