from __future__ import annotations

import pytest

from mhglauncher.errors import AppError
from mhglauncher.services.uigf import import_uigf


def test_rejects_uigf_v3() -> None:
    with pytest.raises(AppError, match="仅支持 UIGF"):
        import_uigf({"info": {"uigf_version": "v3.0"}, "hk4e": []})


def test_rejects_empty_hk4e_data() -> None:
    with pytest.raises(AppError, match="不包含"):
        import_uigf({"info": {"uigf_version": "v4.2"}, "hk4e": []})


@pytest.mark.parametrize("version", ["v4.0", "v4.1", "v4.2"])
def test_imports_supported_uigf_versions(version: str) -> None:
    records = import_uigf(
        {
            "info": {"uigf_version": version},
            "hk4e": [
                {
                    "uid": "100000001",
                    "timezone": 8,
                    "list": [
                        {
                            "id": "1",
                            "uigf_gacha_type": "301",
                            "gacha_type": "301",
                            "item_id": "1001",
                            "name": "测试角色",
                            "item_type": "角色",
                            "rank_type": "5",
                            "time": "2026-06-11 08:00:00",
                        }
                    ],
                }
            ],
        }
    )
    assert records[0].uid == "100000001"
    assert records[0].rank == 5


def test_rejects_malformed_uigf_item() -> None:
    with pytest.raises(AppError, match="字段无效"):
        import_uigf(
            {
                "info": {"uigf_version": "v4.2"},
                "hk4e": [{"uid": "100000001", "list": [{"id": "1"}]}],
            }
        )
