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

