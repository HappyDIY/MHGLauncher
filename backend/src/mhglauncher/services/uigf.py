from __future__ import annotations

from datetime import datetime
from typing import Any

from mhglauncher.errors import AppError
from mhglauncher.models import WishRecord


def import_uigf(payload: dict[str, Any]) -> list[WishRecord]:
    version = str(payload.get("info", {}).get("uigf_version", ""))
    if not version.startswith(("v4.0", "v4.1", "v4.2")):
        raise AppError("uigf_version_unsupported", "仅支持 UIGF v4.0 至 v4.2")
    records: list[WishRecord] = []
    for account in payload.get("hk4e", []):
        uid = str(account.get("uid", ""))
        timezone = int(account.get("timezone", 8))
        for item in account.get("list", []):
            records.append(_record(uid, timezone, item))
    if not records:
        raise AppError("uigf_empty", "UIGF 文件不包含原神祈愿记录")
    return records


def export_uigf(uid: str, records: list[WishRecord]) -> dict[str, Any]:
    return {
        "info": {
            "export_timestamp": int(datetime.now().timestamp()),
            "export_app": "MHGLauncher",
            "export_app_version": "0.1.0",
            "uigf_version": "v4.2",
        },
        "hk4e": [
            {
                "uid": uid,
                "timezone": 8,
                "lang": "zh-cn",
                "list": [
                    {
                        "uigf_gacha_type": item.gacha_type,
                        "gacha_type": item.gacha_type,
                        "item_id": item.item_id,
                        "count": "1",
                        "time": item.time.strftime("%Y-%m-%d %H:%M:%S"),
                        "name": item.name,
                        "item_type": item.item_type,
                        "rank_type": str(item.rank),
                        "id": item.id,
                    }
                    for item in reversed(records)
                ],
            }
        ],
    }


def _record(uid: str, timezone: int, item: dict[str, Any]) -> WishRecord:
    del timezone
    try:
        return WishRecord(
            id=str(item["id"]),
            uid=uid,
            gacha_type=str(item.get("uigf_gacha_type") or item["gacha_type"]),
            item_id=str(item["item_id"]),
            name=str(item["name"]),
            item_type=str(item["item_type"]),
            rank=int(item["rank_type"]),
            time=datetime.strptime(item["time"], "%Y-%m-%d %H:%M:%S"),
        )
    except (KeyError, TypeError, ValueError) as error:
        raise AppError("uigf_item_invalid", "UIGF 记录字段无效") from error

