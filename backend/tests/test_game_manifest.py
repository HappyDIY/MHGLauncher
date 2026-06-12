from __future__ import annotations

import hashlib
import json
from pathlib import Path

from mhglauncher.providers.base import GameAsset, GameBuild, SophonChunk
from mhglauncher.services.game_manifest import hotfix_build


def test_hotfix_build_keeps_only_changed_assets(tmp_path: Path) -> None:
    unchanged = b"same"
    changed = b"old"
    (tmp_path / "same.bin").write_bytes(unchanged)
    (tmp_path / "changed.bin").write_bytes(changed)
    records = [
        {
            "remoteName": "same.bin",
            "md5": _md5(unchanged),
            "hash": "unused",
            "fileSize": len(unchanged),
        },
        {
            "remoteName": "changed.bin",
            "md5": _md5(changed),
            "hash": "unused",
            "fileSize": len(changed),
        },
    ]
    (tmp_path / "pkg_version").write_text(
        "\n".join(json.dumps(item) for item in records),
        encoding="utf-8",
    )
    build = GameBuild(
        version="6.6.0",
        assets=[
            _asset("same.bin", unchanged),
            _asset("changed.bin", b"new"),
            _asset("pkg_version", b"new manifest"),
        ],
    )

    result = hotfix_build(build, tmp_path)

    assert result.kind == "package_repair"
    assert [asset.name for asset in result.assets] == ["changed.bin", "pkg_version"]


def test_hotfix_build_uses_actual_hash_for_manifest_file(tmp_path: Path) -> None:
    content = b"manifest content"
    (tmp_path / "pkg_version").write_bytes(content)
    build = GameBuild(version="6.6.0", assets=[_asset("pkg_version", content)])

    result = hotfix_build(build, tmp_path)

    assert result.assets == []


def _asset(name: str, content: bytes) -> GameAsset:
    return GameAsset(
        name=name,
        size=len(content),
        md5=_md5(content),
        chunks=[
            SophonChunk(
                name=f"{name}-chunk",
                decompressed_md5=_md5(content),
                offset=0,
                size=len(content),
                decompressed_size=len(content),
                url="https://fixture.invalid/chunk",
            )
        ],
    )


def _md5(content: bytes) -> str:
    return hashlib.md5(content, usedforsecurity=False).hexdigest()
