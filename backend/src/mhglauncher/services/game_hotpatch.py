from __future__ import annotations

import json
from pathlib import Path

from mhglauncher.providers.base import GameBuild

PERSISTENT_DIR = Path("YuanShen_Data/Persistent")
REMOTE_MANIFESTS = (
    "data_versions_remote",
    "res_versions_remote",
    "silence_data_versions_remote",
)


def pending_hotpatch(build: GameBuild, install_path: Path) -> GameBuild:
    persistent = install_path / PERSISTENT_DIR
    size = sum(_pending_size(persistent / name) for name in REMOTE_MANIFESTS)
    if size == 0:
        return build
    return build.model_copy(
        update={
            "kind": "game_hotfix",
            "pending_bytes": size,
        }
    )


def _pending_size(path: Path) -> int:
    if not path.is_file():
        return 0
    total = 0
    for line in path.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        try:
            item = json.loads(line)
            total += max(int(item.get("fileSize", 0)), 0)
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
    return total
