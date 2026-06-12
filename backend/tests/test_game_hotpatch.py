from __future__ import annotations

import json
from pathlib import Path

from mhglauncher.providers.base import GameBuild
from mhglauncher.services.game_hotpatch import pending_hotpatch


def test_pending_hotpatch_reads_game_remote_manifests(tmp_path: Path) -> None:
    persistent = tmp_path / "YuanShen_Data/Persistent"
    persistent.mkdir(parents=True)
    records = [
        {"remoteName": "blocks/a.blk", "fileSize": 1024, "isPatch": True},
        {"remoteName": "blocks/b.blk", "fileSize": 2048},
    ]
    (persistent / "data_versions_remote").write_text(
        "\n".join(json.dumps(item) for item in records),
        encoding="utf-8",
    )

    result = pending_hotpatch(GameBuild(version="6.6.0"), tmp_path)

    assert result.kind == "game_hotfix"
    assert result.pending_bytes == 3072


def test_pending_hotpatch_ignores_persisted_manifests(tmp_path: Path) -> None:
    persistent = tmp_path / "YuanShen_Data/Persistent"
    persistent.mkdir(parents=True)
    (persistent / "data_versions_persist").write_text(
        json.dumps({"remoteName": "blocks/a.blk", "fileSize": 1024}),
        encoding="utf-8",
    )

    result = pending_hotpatch(GameBuild(version="6.6.0"), tmp_path)

    assert result.kind == "full"
    assert result.pending_bytes == 0
