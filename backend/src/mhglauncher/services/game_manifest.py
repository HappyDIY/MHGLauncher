from __future__ import annotations

import hashlib
import json
from pathlib import Path

from mhglauncher.providers.base import GameAsset, GameBuild

MANIFEST_NAMES = (
    "pkg_version",
    "Audio_Chinese_pkg_version",
)


def hotfix_build(build: GameBuild, install_path: Path) -> GameBuild:
    local = _read_local_hashes(install_path)
    changed = [
        asset
        for asset in build.assets
        if _local_hash(asset, install_path, local) != asset.md5.lower()
    ]
    return build.model_copy(update={"assets": changed, "kind": "hotfix"})


def _read_local_hashes(install_path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for name in MANIFEST_NAMES:
        path = install_path / name
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
            try:
                item = json.loads(line)
                remote = str(item["remoteName"]).replace("\\", "/")
                result[remote] = str(item["md5"]).lower()
            except (json.JSONDecodeError, KeyError, TypeError):
                continue
    return result


def _local_hash(
    asset: GameAsset,
    install_path: Path,
    hashes: dict[str, str],
) -> str:
    name = asset.name.replace("\\", "/")
    if name in hashes:
        return hashes[name]
    path = install_path / name
    return _md5(path) if path.is_file() else ""


def _md5(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()
