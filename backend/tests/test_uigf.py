from __future__ import annotations

from datetime import datetime

import pytest

from mhglauncher.errors import AppError
from mhglauncher.models import WishRecord
from mhglauncher.services.uigf import export_uigf, import_uigf


def _payload(version: str = "v4.2") -> dict[str, object]:
    return {
        "info": {
            "export_timestamp": 1,
            "export_app": "测试应用",
            "export_app_version": "1.0",
            "version": version,
        },
        "hk4e": [
            {
                "uid": 100000001,
                "timezone": 8,
                "list": [
                    {
                        "id": 1,
                        "uigf_gacha_type": 301,
                        "gacha_type": 400,
                        "item_id": 1001,
                        "time": "2026-06-11 08:00:00",
                    }
                ],
            }
        ],
    }


@pytest.mark.parametrize("version", ["v4.0", "v4.1", "v4.2"])
def test_imports_supported_versions_and_number_fields(version: str) -> None:
    records = import_uigf(_payload(version))
    assert records[0].uid == "100000001"
    assert records[0].gacha_type == "400"
    assert records[0].uigf_gacha_type == "301"
    assert records[0].name == ""
    assert records[0].rank == 0


@pytest.mark.parametrize("version", ["v3.0", "v4.3", "v5.0", "unknown"])
def test_rejects_unsupported_versions(version: str) -> None:
    with pytest.raises(AppError, match=r"v4\.0、v4\.1 或 v4\.2"):
        import_uigf(_payload(version))


def test_rejects_legacy_version_key() -> None:
    payload = _payload()
    info = payload["info"]
    assert isinstance(info, dict)
    info["uigf_version"] = info.pop("version")
    with pytest.raises(AppError, match="请先升级"):
        import_uigf(payload)


def test_rejects_empty_hk4e_data() -> None:
    payload = _payload()
    payload["hk4e"] = []
    with pytest.raises(AppError, match="不包含"):
        import_uigf(payload)


def test_rejects_malformed_uigf_item() -> None:
    payload = _payload()
    account = payload["hk4e"]
    assert isinstance(account, list)
    account[0]["list"] = [{"id": "1"}]
    with pytest.raises(AppError, match="不符合"):
        import_uigf(payload)


def test_exports_standard_v42_and_preserves_gacha_types() -> None:
    record = WishRecord(
        id="1",
        uid="600000001",
        gacha_type="400",
        uigf_gacha_type="301",
        item_id="1001",
        name="测试角色",
        item_type="角色",
        rank=5,
        time=datetime(2026, 6, 11, 8),
    )
    exported = export_uigf(record.uid, [record])
    assert exported["info"]["version"] == "v4.2"
    assert "uigf_version" not in exported["info"]
    assert exported["hk4e"][0]["timezone"] == -5
    item = exported["hk4e"][0]["list"][0]
    assert item["gacha_type"] == "400"
    assert item["uigf_gacha_type"] == "301"
