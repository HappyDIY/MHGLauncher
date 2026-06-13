from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from mhglauncher import __version__
from mhglauncher.errors import AppError
from mhglauncher.models import WishRecord
from mhglauncher.services.item_metadata import enrich_record

UIGFVersion = Literal["v4.0", "v4.1", "v4.2"]
GACHA_TYPES = {"100", "200", "301", "302", "400", "500"}
UIGF_GACHA_TYPES = {"100", "200", "301", "302", "500"}


class UIGFInfo(BaseModel):
    model_config = ConfigDict(extra="ignore")

    export_timestamp: str | int
    export_app: str
    export_app_version: str
    version: UIGFVersion


class UIGFItem(BaseModel):
    model_config = ConfigDict(extra="ignore")

    uigf_gacha_type: str
    gacha_type: str
    item_id: str
    count: str = "1"
    time: str
    name: str = ""
    item_type: str = ""
    rank_type: str | None = None
    id: str = Field(min_length=1, max_length=19, pattern=r"^[0-9]+$")

    @field_validator(
        "uigf_gacha_type",
        "gacha_type",
        "item_id",
        "count",
        "rank_type",
        "id",
        mode="before",
    )
    @classmethod
    def stringify_numbers(cls, value: Any) -> Any:
        return str(value) if isinstance(value, int) else value

    @field_validator("uigf_gacha_type")
    @classmethod
    def validate_uigf_gacha_type(cls, value: str) -> str:
        if value not in UIGF_GACHA_TYPES:
            raise ValueError("unsupported UIGF gacha type")
        return value

    @field_validator("gacha_type")
    @classmethod
    def validate_gacha_type(cls, value: str) -> str:
        if value not in GACHA_TYPES:
            raise ValueError("unsupported gacha type")
        return value


class UIGFAccount(BaseModel):
    model_config = ConfigDict(extra="ignore")

    uid: str
    timezone: int
    lang: str | None = None
    list: list[UIGFItem]

    @field_validator("uid", mode="before")
    @classmethod
    def stringify_uid(cls, value: Any) -> Any:
        return str(value) if isinstance(value, int) else value


class UIGFFile(BaseModel):
    model_config = ConfigDict(extra="ignore")

    info: UIGFInfo
    hk4e: list[UIGFAccount] = Field(default_factory=list)


def import_uigf(payload: dict[str, Any]) -> list[WishRecord]:
    _reject_legacy_version(payload)
    try:
        document = UIGFFile.model_validate(payload)
        records = [_record(account, item) for account in document.hk4e for item in account.list]
    except ValidationError as error:
        raise AppError("uigf_invalid", "UIGF 文件不符合 v4.0、v4.1 或 v4.2 规范") from error
    if not records:
        raise AppError("uigf_empty", "UIGF 文件不包含原神祈愿记录")
    return records


def export_uigf(uid: str, records: list[WishRecord]) -> dict[str, Any]:
    return {
        "info": {
            "export_timestamp": int(datetime.now(UTC).timestamp()),
            "export_app": "MHGLauncher",
            "export_app_version": __version__,
            "version": "v4.2",
        },
        "hk4e": [
            {
                "uid": uid,
                "timezone": _timezone(uid),
                "lang": "zh-cn",
                "list": [_export_item(item) for item in reversed(records)],
            }
        ],
    }


def _record(account: UIGFAccount, item: UIGFItem) -> WishRecord:
    try:
        parsed_time = datetime.strptime(item.time, "%Y-%m-%d %H:%M:%S")
        rank = int(item.rank_type) if item.rank_type is not None else 0
        return enrich_record(
            WishRecord(
                id=item.id,
                uid=account.uid,
                gacha_type=item.gacha_type,
                uigf_gacha_type=item.uigf_gacha_type,
                item_id=item.item_id,
                name=item.name,
                item_type=item.item_type,
                rank=rank,
                time=parsed_time,
            )
        )
    except (TypeError, ValueError) as error:
        raise AppError("uigf_item_invalid", "UIGF 记录字段无效") from error


def _export_item(item: WishRecord) -> dict[str, str]:
    result = {
        "uigf_gacha_type": item.uigf_gacha_type or _uigf_type(item.gacha_type),
        "gacha_type": item.gacha_type,
        "item_id": item.item_id,
        "count": "1",
        "time": item.time.strftime("%Y-%m-%d %H:%M:%S"),
        "id": item.id,
    }
    if item.name:
        result["name"] = item.name
    if item.item_type:
        result["item_type"] = item.item_type
    if item.rank:
        result["rank_type"] = str(item.rank)
    return result


def _reject_legacy_version(payload: dict[str, Any]) -> None:
    info = payload.get("info")
    if isinstance(info, dict) and "uigf_version" in info and "version" not in info:
        raise AppError("uigf_legacy", "仅支持 UIGF v4.0、v4.1、v4.2，请先升级旧版文件")


def _uigf_type(gacha_type: str) -> str:
    return "301" if gacha_type == "400" else gacha_type


def _timezone(uid: str) -> int:
    if uid.startswith("6"):
        return -5
    if uid.startswith("7"):
        return 1
    return 8
