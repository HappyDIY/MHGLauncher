from __future__ import annotations

import json
from functools import lru_cache
from importlib.resources import files
from typing import NamedTuple

from mhglauncher.models import WishRecord


class ItemMetadata(NamedTuple):
    name: str
    item_type: str
    rank: int
    icon: str


@lru_cache(maxsize=1)
def item_metadata() -> dict[str, ItemMetadata]:
    resource = files("mhglauncher").joinpath("data/gacha_items.json")
    payload = json.loads(resource.read_text(encoding="utf-8"))
    return {
        item_id: ItemMetadata(
            str(value[0]),
            str(value[1]),
            int(value[2]),
            str(value[3]) if len(value) > 3 else "",
        )
        for item_id, value in payload.items()
    }


def enrich_record(record: WishRecord) -> WishRecord:
    metadata = item_metadata().get(record.item_id)
    if metadata is None:
        return record
    return record.model_copy(
        update={
            "name": record.name or metadata.name,
            "item_type": record.item_type or metadata.item_type,
            "rank": record.rank or metadata.rank,
            "icon_url": _icon_url(metadata),
        }
    )


def _icon_url(metadata: ItemMetadata) -> str:
    if not metadata.icon:
        return ""
    if metadata.item_type == "角色":
        category = "GachaAvatarIcon"
        icon = metadata.icon.replace("UI_AvatarIcon_", "UI_Gacha_AvatarIcon_", 1)
    else:
        category = "GachaEquipIcon"
        icon = metadata.icon.replace("UI_", "UI_Gacha_", 1)
    return (
        f"https://api.snaphutaorp.org/static/raw/{category}/"
        f"{icon}.png"
    )
