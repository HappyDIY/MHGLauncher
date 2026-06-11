from __future__ import annotations

import json
import zipfile
from pathlib import Path

import pytest

from mhglauncher.errors import AppError
from mhglauncher.services.installer import Installer


def test_extracts_and_verifies_fixture_package(tmp_path: Path) -> None:
    archive = tmp_path / "game.zip"
    staging = tmp_path / "staging"
    with zipfile.ZipFile(archive, "w") as package:
        package.writestr("Genshin Impact Game/config.ini", "version=1")
        package.writestr("mhg-manifest.json", json.dumps({"files": {}}))
    installer = Installer()
    installer.extract([archive], staging)
    installer.verify(staging)
    assert (staging / "Genshin Impact Game/config.ini").read_text() == "version=1"


def test_rejects_path_traversal(tmp_path: Path) -> None:
    archive = tmp_path / "unsafe.zip"
    with zipfile.ZipFile(archive, "w") as package:
        package.writestr("../escape", "bad")
    with pytest.raises(AppError, match="路径不安全"):
        Installer().extract([archive], tmp_path / "staging")


def test_activation_replaces_old_install(tmp_path: Path) -> None:
    destination = tmp_path / "game"
    staging = tmp_path / "staging"
    destination.mkdir()
    staging.mkdir()
    (destination / "old").write_text("old")
    (staging / "new").write_text("new")
    Installer().activate(staging, destination)
    assert not (destination / "old").exists()
    assert (destination / "new").read_text() == "new"

