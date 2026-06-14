"""本地图片缓存服务, 预下载祈愿记录插图到本地磁盘。"""
from __future__ import annotations

import asyncio
import hashlib
from pathlib import Path

import httpx


class ImageCacheService:
    """管理祈愿记录插图的本地缓存与本地代理 URL 生成。"""

    def __init__(self, data_dir: Path, client: httpx.AsyncClient) -> None:
        self._cache_dir = data_dir / "cache" / "images"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._client = client
        self._locks: dict[str, asyncio.Lock] = {}
        self._urls: dict[str, str] = {}

    @property
    def cache_dir(self) -> Path:
        return self._cache_dir

    def local_url(self, remote_url: str, port: int) -> str:
        """将远程 CDN 地址转换为本地 HTTP 代理地址。"""
        if not remote_url or port <= 0:
            return remote_url
        filename = self._hash_filename(remote_url)
        self._urls[filename] = remote_url
        return f"http://127.0.0.1:{port}/v1/images/gacha/{filename}"

    async def ensure(self, remote_url: str) -> Path | None:
        """确保指定远程图片已下载到本地缓存。"""
        if not remote_url:
            return None
        filename = self._hash_filename(remote_url)
        local_path = self._cache_dir / filename
        if local_path.exists() and local_path.stat().st_size > 0:
            return local_path
        lock = self._locks.setdefault(filename, asyncio.Lock())
        async with lock:
            if local_path.exists() and local_path.stat().st_size > 0:
                return local_path
            try:
                response = await self._client.get(remote_url, timeout=30)
                response.raise_for_status()
                local_path.write_bytes(response.content)
            except Exception:
                if local_path.exists():
                    local_path.unlink(missing_ok=True)
                raise
        return local_path

    async def ensure_all(self, urls: list[str]) -> None:
        """批量确保图片已缓存, 不阻断正常流程。"""
        tasks = [self.ensure(url) for url in urls if url]
        await asyncio.gather(*tasks, return_exceptions=True)

    async def get_or_download(self, filename: str) -> Path | None:
        """获取缓存图片, 缓存缺失时尝试按映射远程下载。"""
        local_path = self._cache_dir / filename
        if local_path.exists() and local_path.stat().st_size > 0:
            return local_path
        remote_url = self._urls.get(filename)
        if remote_url is None:
            return None
        return await self.ensure(remote_url)

    def remote_urls(self) -> list[str]:
        """返回当前已映射的全部远程下载地址。"""
        return list(self._urls.values())

    @staticmethod
    def _hash_filename(url: str) -> str:
        return hashlib.sha1(url.encode()).hexdigest() + ".png"
