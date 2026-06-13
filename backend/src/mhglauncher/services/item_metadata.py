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


@lru_cache(maxsize=1)
def item_metadata() -> dict[str, ItemMetadata]:
    resource = files("mhglauncher").joinpath("data/gacha_items.json")
    payload = json.loads(resource.read_text(encoding="utf-8"))
    return {
        item_id: ItemMetadata(str(value[0]), str(value[1]), int(value[2]))
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
        }
    )
