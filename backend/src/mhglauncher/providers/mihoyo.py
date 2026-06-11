from __future__ import annotations

import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlencode

import httpx

from mhglauncher.errors import AppError
from mhglauncher.models import DailyNote, GameRole, WishRecord
from mhglauncher.providers.signing import cookie_map, data_sign

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1"


class MihoyoAPI:
    def __init__(self, client: httpx.AsyncClient, device_id: str) -> None:
        self.client = client
        self.device_id = device_id

    async def enrich_credential(self, credential: str) -> str:
        cookies = cookie_map(credential)
        headers = self._headers(credential, data_sign("prod", body="{}"))
        url = "https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken"
        data = self._data(await self.client.get(url, headers=headers))
        cookies["cookie_token"] = str(data["cookie_token"])
        cookies["account_id"] = str(data["uid"])
        return "; ".join(f"{key}={value}" for key, value in cookies.items())

    async def roles(self, credential: str) -> list[GameRole]:
        url = "https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByStoken"
        headers = self._headers(credential, data_sign("lk2", generation=1))
        data = self._data(await self.client.get(url, headers=headers))
        return [
            GameRole(
                uid=str(item["game_uid"]),
                nickname=str(item["nickname"]),
                region=str(item["region"]),
                level=int(item["level"]),
                selected=bool(item.get("is_chosen")),
            )
            for item in data.get("list", [])
            if item.get("game_biz") == "hk4e_cn"
        ]

    async def wishes(
        self,
        credential: str,
        role: GameRole,
        end_id: str,
    ) -> AsyncIterator[list[WishRecord]]:
        authkey = await self._authkey(credential, role)
        for gacha_type in ("100", "200", "301", "302"):
            current = end_id
            while True:
                query = {
                    "auth_appid": "webview_gacha",
                    "authkey_ver": "1",
                    "sign_type": "2",
                    "authkey": authkey,
                    "lang": "zh-cn",
                    "gacha_type": gacha_type,
                    "size": "20",
                    "end_id": current,
                }
                url = "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog"
                data = self._data(await self.client.get(url, params=query))
                records = [self._wish(role.uid, item) for item in data.get("list", [])]
                if not records:
                    break
                yield records
                current = records[-1].id
                if len(records) < 20:
                    break

    async def note(self, credential: str, role: GameRole) -> DailyNote:
        query = urlencode({"role_id": role.uid, "server": role.region})
        url = f"https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote?{query}"
        headers = self._headers(credential, data_sign("x4", query=query))
        headers["Referer"] = "https://webstatic.mihoyo.com/"
        data = self._data(await self.client.get(url, headers=headers))
        expeditions = data.get("expeditions", [])
        transformer = data.get("transformer", {})
        recovery = transformer.get("recovery_time", {})
        return DailyNote(
            uid=role.uid,
            current_resin=int(data.get("current_resin", 0)),
            max_resin=int(data.get("max_resin", 200)),
            finished_tasks=int(data.get("finished_task_num", 0)),
            total_tasks=int(data.get("total_task_num", 4)),
            expeditions_finished=sum(item.get("status") == "Finished" for item in expeditions),
            expeditions_total=int(data.get("max_expedition_num", len(expeditions))),
            current_home_coin=int(data.get("current_home_coin", 0)),
            max_home_coin=int(data.get("max_home_coin", 0)),
            weekly_boss_remaining=int(data.get("remain_resin_discount_num", 0)),
            transformer_ready=bool(recovery.get("reached", False)),
            refreshed_at=datetime.now(UTC),
        )

    async def _authkey(self, credential: str, role: GameRole) -> str:
        payload = {
            "auth_appid": "webview_gacha",
            "game_biz": "hk4e_cn",
            "game_uid": int(role.uid),
            "region": role.region,
        }
        body = json.dumps(payload, separators=(",", ":"))
        headers = self._headers(credential, data_sign("lk2", generation=1))
        url = "https://api-takumi.mihoyo.com/binding/api/genAuthKey"
        data = self._data(await self.client.post(url, content=body, headers=headers))
        return str(data["authkey"])

    def _headers(self, credential: str, sign: str) -> dict[str, str]:
        return {
            "Cookie": credential,
            "DS": sign,
            "User-Agent": USER_AGENT,
            "x-rpc-app_version": "2.95.1",
            "x-rpc-client_type": "5",
            "x-rpc-device_id": self.device_id,
            "Content-Type": "application/json",
        }

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError("mihoyo_error", str(payload.get("message", "米游社请求失败")), 502)
        data: dict[str, Any] = payload.get("data") or {}
        return data

    @staticmethod
    def _wish(uid: str, item: dict[str, Any]) -> WishRecord:
        return WishRecord(
            id=str(item["id"]),
            uid=uid,
            gacha_type=str(item["gacha_type"]),
            item_id=str(item["item_id"]),
            name=str(item["name"]),
            item_type=str(item["item_type"]),
            rank=int(item["rank_type"]),
            time=datetime.strptime(item["time"], "%Y-%m-%d %H:%M:%S"),
        )

