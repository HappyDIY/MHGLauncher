from __future__ import annotations

import json
from functools import lru_cache
from importlib.resources import files
from typing import TYPE_CHECKING, NamedTuple

from mhglauncher.models import WishRecord

if TYPE_CHECKING:
    from mhglauncher.services.image_cache import ImageCacheService


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


@lru_cache(maxsize=1)
def item_metadata_by_name() -> dict[str, tuple[str, ItemMetadata]]:
    return {metadata.name: (item_id, metadata) for item_id, metadata in item_metadata().items()}


def enrich_record(
    record: WishRecord,
    image_cache: ImageCacheService | None = None,
    port: int = 0,
) -> WishRecord:
    metadata = item_metadata().get(record.item_id)
    item_id = record.item_id
    if metadata is None and record.name:
        matched = item_metadata_by_name().get(record.name)
        if matched is not None:
            item_id, metadata = matched
    if metadata is None:
        return record
    icon_url = _icon_url(metadata)
    if image_cache is not None and port > 0:
        icon_url = image_cache.local_url(icon_url, port)
    return record.model_copy(
        update={
            "item_id": item_id,
            "name": record.name or metadata.name,
            "item_type": record.item_type or metadata.item_type,
            "rank": record.rank or metadata.rank,
            "icon_url": icon_url,
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
    return f"https://api.snaphutaorp.org/static/raw/{category}/{icon}.png"


def remote_icon_urls(item_ids: set[str]) -> list[str]:
    """获取一组 item_id 对应的远程 CDN 地址。"""
    metadata_map = item_metadata()
    urls: list[str] = []
    for item_id in item_ids:
        metadata = metadata_map.get(item_id)
        if metadata and metadata.icon:
            urls.append(_icon_url(metadata))
    return urls
