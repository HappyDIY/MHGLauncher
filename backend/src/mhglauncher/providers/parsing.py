from __future__ import annotations

from datetime import datetime
from typing import Any

from mhglauncher.models import WishRecord


def wish_record(uid: str, item: dict[str, Any]) -> WishRecord:
    return WishRecord(
        id=str(item["id"]),
        uid=uid,
        gacha_type=str(item["gacha_type"]),
        item_id=str(item["item_id"]),
        name=str(item["name"]),
        item_type=str(item["item_type"]),
        rank=int(item["rank_type"]),
        time=datetime.strptime(item["time"], "%Y-%m-%d %H:%M:%S"),
    )
