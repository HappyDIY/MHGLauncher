from __future__ import annotations

import configparser
from pathlib import Path


def detect_game(path: Path) -> tuple[Path, str] | None:
    candidates = (path, path / "Genshin Impact Game")
    for candidate in candidates:
        marker = candidate / ".mhg-version"
        if marker.is_file():
            version = _read_marker(marker)
            if version:
                return candidate, version
        executable = candidate / "YuanShen.exe"
        config_path = candidate / "config.ini"
        if not executable.is_file() or not config_path.is_file():
            continue
        version = _read_version(config_path)
        if version:
            return candidate, version
    return None


def _read_marker(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return ""


def _read_version(path: Path) -> str:
    parser = configparser.ConfigParser(interpolation=None)
    try:
        with path.open(encoding="utf-8-sig") as stream:
            parser.read_file(stream)
    except (OSError, UnicodeError, configparser.Error):
        return ""
    return parser.get("General", "game_version", fallback="").strip()
