from __future__ import annotations

import json
from pathlib import Path

from mhglauncher.providers.base import GameBuild


def download_size(build: GameBuild) -> int:
    patches = {asset.patch.id: asset.patch.file_size for asset in build.patch_assets}
    return (
        sum(item.size for item in build.segments)
        + sum(chunk.size for asset in build.assets for chunk in asset.chunks)
        + sum(patches.values())
    )


def remove_retired_assets(staging: Path, build: GameBuild) -> None:
    manifest = staging / ".mhg-assets.json"
    if not manifest.is_file():
        return
    current = {asset.name for asset in build.assets}
    previous: list[str] = json.loads(manifest.read_text())
    remove_files(staging, list(set(previous) - current))


def remove_files(staging: Path, files: list[str]) -> None:
    root = staging.resolve()
    for relative in files:
        target = staging / relative.replace("\\", "/")
        if root in target.resolve().parents:
            target.unlink(missing_ok=True)
