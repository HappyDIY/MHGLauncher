from __future__ import annotations

import asyncio
import random
from collections.abc import AsyncIterator
from typing import Any

import httpx

from mhglauncher.errors import AppError
from mhglauncher.models import GameRole, WishRecord
from mhglauncher.providers.parsing import wish_record


class GachaLogClient:
    URL = "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog"

    def __init__(self, client: httpx.AsyncClient, delay: bool = True) -> None:
        self.client = client
        self.delay = delay
        self.requested = False

    async def pages(
        self,
        authkey: str,
        role: GameRole,
        newest_ids: dict[str, str],
    ) -> AsyncIterator[list[WishRecord]]:
        self.requested = False
        for gacha_type in ("100", "200", "301", "302"):
            current = "0"
            newest_id = newest_ids.get(gacha_type)
            while True:
                data = await self._request(authkey, gacha_type, current)
                records = [wish_record(role.uid, item) for item in data.get("list", [])]
                fresh = self._fresh_records(records, newest_id)
                if fresh:
                    yield fresh
                if len(fresh) < len(records) or len(records) < 20:
                    break
                current = records[-1].id

    async def _request(
        self,
        authkey: str,
        gacha_type: str,
        end_id: str,
    ) -> dict[str, Any]:
        await self._wait()
        query = {
            "auth_appid": "webview_gacha",
            "authkey_ver": "1",
            "sign_type": "2",
            "authkey": authkey,
            "lang": "zh-cn",
            "gacha_type": gacha_type,
            "size": "20",
            "end_id": end_id,
        }
        for attempt in range(3):
            response = await self.client.get(self.URL, params=query)
            response.raise_for_status()
            payload = response.json()
            if payload.get("retcode", 0) == 0:
                return payload.get("data") or {}
            if not self._is_frequent(payload):
                self._raise(payload)
            if attempt < 2:
                await self._sleep(2 ** (attempt + 1))
        raise AppError(
            "mihoyo_rate_limited",
            "米游社访问过于频繁，请稍候一分钟后再同步",
            429,
        )

    async def _wait(self) -> None:
        if self.requested:
            await self._sleep(random.uniform(1, 2))
        self.requested = True

    async def _sleep(self, seconds: float) -> None:
        if self.delay:
            await asyncio.sleep(seconds)

    @staticmethod
    def _fresh_records(
        records: list[WishRecord],
        newest_id: str | None,
    ) -> list[WishRecord]:
        if newest_id is None:
            return records
        for index, record in enumerate(records):
            if record.id == newest_id:
                return records[:index]
        return records

    @staticmethod
    def _is_frequent(payload: dict[str, Any]) -> bool:
        message = str(payload.get("message", "")).casefold()
        return "too frequent" in message or "频繁" in message

    @staticmethod
    def _raise(payload: dict[str, Any]) -> None:
        retcode = payload.get("retcode")
        message = str(payload.get("message", "")).strip()
        raise AppError(
            "mihoyo_error",
            message or f"米游社请求失败（错误码 {retcode}）",
            502,
            {"retcode": str(retcode)},
        )
