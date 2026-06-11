from __future__ import annotations

import hashlib
import json
import shutil
import zipfile
from pathlib import Path, PurePosixPath

from mhglauncher.errors import AppError


class Installer:
    def extract(self, archives: list[Path], staging: Path) -> None:
        staging.mkdir(parents=True, exist_ok=True)
        for archive in archives:
            if not zipfile.is_zipfile(archive):
                raise AppError("archive_unsupported", f"{archive.name} 不是受支持的 ZIP 包")
            with zipfile.ZipFile(archive) as package:
                for item in package.infolist():
                    target = _safe_target(staging, item.filename)
                    if item.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                        continue
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with package.open(item) as source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)

    def verify(self, staging: Path) -> None:
        manifest_path = staging / "mhg-manifest.json"
        if not manifest_path.exists():
            return
        payload = json.loads(manifest_path.read_text())
        for relative, expected in payload.get("files", {}).items():
            target = _safe_target(staging, relative)
            if not target.is_file() or _sha256(target) != expected:
                raise AppError("installed_file_invalid", f"{relative} 安装校验失败")

    def activate(self, staging: Path, destination: Path) -> None:
        backup = destination.with_name(destination.name + ".backup")
        shutil.rmtree(backup, ignore_errors=True)
        if destination.exists():
            destination.replace(backup)
        try:
            staging.replace(destination)
        except BaseException:
            if backup.exists() and not destination.exists():
                backup.replace(destination)
            raise
        shutil.rmtree(backup, ignore_errors=True)


def _safe_target(root: Path, relative: str) -> Path:
    value = PurePosixPath(relative)
    if value.is_absolute() or ".." in value.parts:
        raise AppError("archive_path_unsafe", f"压缩包路径不安全：{relative}")
    target = root.joinpath(*value.parts)
    if root.resolve() not in target.resolve().parents and target.resolve() != root.resolve():
        raise AppError("archive_path_unsafe", f"压缩包路径不安全：{relative}")
    return target


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()

