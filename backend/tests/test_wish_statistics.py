from datetime import datetime, timedelta

from mhglauncher.models import WishRecord
from mhglauncher.services.wish_statistics import build_banner_detail


def _record(index: int, rank: int) -> WishRecord:
    return WishRecord(
        id=str(index),
        uid="100000001",
        gacha_type="301",
        item_id="10000079" if rank == 5 else "11402",
        name="芙宁娜" if rank == 5 else "笛剑",
        item_type="角色" if rank == 5 else "武器",
        rank=rank,
        time=datetime(2026, 1, 1) + timedelta(minutes=index),
    )


def test_banner_items_report_cycle_pity_not_absolute_position() -> None:
    records = [
        *[_record(index, 3) for index in range(1, 11)],
        _record(11, 5),
        *[_record(index, 3) for index in range(12, 31)],
        _record(31, 5),
    ]

    detail = build_banner_detail("100000001", "301", records)

    assert [item.pull_number for item in detail.five_star_items] == [31, 11]
    assert [item.pity for item in detail.five_star_items] == [20, 11]
    assert detail.average_pity == 15.5
    assert detail.last_pity == 0


def test_purple_item_reports_its_own_cycle_pity() -> None:
    records = [
        _record(1, 3),
        _record(2, 3),
        _record(3, 4),
        _record(4, 3),
        _record(5, 4),
    ]

    detail = build_banner_detail("100000001", "301", records)

    assert [item.pity for item in detail.four_star_items] == [2, 3]
