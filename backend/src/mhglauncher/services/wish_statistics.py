"""祈愿统计算法, 参考 Snap.Hutao 的 TypedWishSummary 实现。"""

from __future__ import annotations

import builtins
from typing import TYPE_CHECKING

from mhglauncher.models import WishBannerDetail, WishBannerItem, WishRecord
from mhglauncher.services.item_metadata import enrich_record

if TYPE_CHECKING:
    from mhglauncher.services.image_cache import ImageCacheService


def guarantee_threshold(gacha_type: str) -> int:
    return 80 if gacha_type == "302" else 90


def build_banner_detail(
    uid: str,
    gacha_type: str,
    items: builtins.list[WishRecord],
    image_cache: ImageCacheService | None = None,
    port: int = 0,
) -> WishBannerDetail:
    threshold = guarantee_threshold(gacha_type)
    orange_pity = 0
    purple_pity = 0
    pull_number = 0
    orange_distances: builtins.list[int] = []
    orange_items: builtins.list[WishBannerItem] = []
    purple_items: builtins.list[WishBannerItem] = []
    five_star_count = 0
    four_star_count = 0
    three_star_count = 0
    max_pity = 0
    min_pity = 0

    for item in items:
        pull_number += 1
        orange_pity += 1
        purple_pity += 1
        rank = item.rank
        if rank == 5:
            item_pity = orange_pity
            if orange_pity < min_pity or min_pity == 0:
                min_pity = orange_pity
            if orange_pity > max_pity or max_pity == 0:
                max_pity = orange_pity
            orange_distances.append(orange_pity)
            orange_pity = 0
            purple_pity = 0
            five_star_count += 1
            enriched = enrich_record(item, image_cache, port)
            orange_items.append(
                WishBannerItem(
                    name=enriched.name,
                    item_id=enriched.item_id,
                    item_type=enriched.item_type,
                    rank=rank,
                    icon_url=enriched.icon_url,
                    pull_number=pull_number,
                    pity=item_pity,
                    time=item.time,
                )
            )
        elif rank == 4:
            item_pity = purple_pity
            purple_pity = 0
            four_star_count += 1
            enriched = enrich_record(item, image_cache, port)
            purple_items.append(
                WishBannerItem(
                    name=enriched.name,
                    item_id=enriched.item_id,
                    item_type=enriched.item_type,
                    rank=rank,
                    icon_url=enriched.icon_url,
                    pull_number=pull_number,
                    pity=item_pity,
                    time=item.time,
                )
            )
        elif rank == 3:
            three_star_count += 1

    total = pull_number
    five_star_percent = five_star_count / total if total > 0 else 0.0
    four_star_percent = four_star_count / total if total > 0 else 0.0
    three_star_percent = three_star_count / total if total > 0 else 0.0
    average_pity = sum(orange_distances) / len(orange_distances) if orange_distances else 0.0

    return WishBannerDetail(
        uid=uid,
        gacha_type=gacha_type,
        total=total,
        time_from=items[0].time if items else None,
        time_to=items[-1].time if items else None,
        five_star_count=five_star_count,
        four_star_count=four_star_count,
        three_star_count=three_star_count,
        five_star_percent=round(five_star_percent, 4),
        four_star_percent=round(four_star_percent, 4),
        three_star_percent=round(three_star_percent, 4),
        max_pity=max_pity,
        min_pity=min_pity if min_pity > 0 else 0,
        average_pity=round(average_pity, 2),
        last_pity=orange_pity,
        last_purple_pity=purple_pity,
        guarantee_threshold=threshold,
        five_star_items=list(reversed(orange_items)),
        four_star_items=list(reversed(purple_items)),
    )
