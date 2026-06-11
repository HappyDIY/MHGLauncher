from __future__ import annotations

import json
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlencode

import httpx

from mhglauncher.errors import AppError
from mhglauncher.models import DailyNote, GameRole, WishRecord
from mhglauncher.providers.device import DeviceIdentity
from mhglauncher.providers.gacha import GachaLogClient
from mhglauncher.providers.signing import cookie_map, data_sign
from mhglauncher.providers.verification import MihoyoVerification

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1"

class MihoyoAPI:
    def __init__(self, client: httpx.AsyncClient, device: DeviceIdentity) -> None:
        self.client = client
        self.device = device
        self.gacha = GachaLogClient(client)
        self.verification = MihoyoVerification(client, device)

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
        newest_ids: dict[str, str],
    ) -> AsyncIterator[list[WishRecord]]:
        authkey = await self._authkey(credential, role)
        async for page in self.gacha.pages(authkey, role, newest_ids):
            yield page

    async def note(
        self,
        credential: str,
        role: GameRole,
        xrpc_challenge: str = "",
    ) -> DailyNote:
        query = urlencode({"role_id": role.uid, "server": role.region})
        url = f"https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote?{query}"
        await self.device.ensure_fingerprint(self.client)
        headers = self._headers(credential, data_sign("x4", query=query))
        headers["Referer"] = "https://webstatic.mihoyo.com/"
        headers["x-rpc-tool_verison"] = "v5.0.1-ys"
        if xrpc_challenge:
            headers["x-rpc-challenge"] = xrpc_challenge
        await self._prime_game_record(credential, role)
        response = await self.client.get(url, headers=headers)
        payload = response.json()
        if payload.get("retcode") == 1034:
            raise AppError(
                "verification_required",
                "请完成人机验证后重试",
                428,
                await self.verification.create(credential),
            )
        data = self._data(response)
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

    async def _prime_game_record(self, credential: str, role: GameRole) -> None:
        query = urlencode({"role_id": role.uid, "server": role.region})
        url = f"https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/index?{query}"
        headers = self._headers(credential, data_sign("x4", query=query))
        headers["Referer"] = "https://webstatic.mihoyo.com/"
        response = await self.client.get(url, headers=headers)
        if response.status_code < 500 and response.json().get("retcode") != 1034:
            self._data(response)

    async def verify_challenge(
        self,
        credential: str,
        challenge: str,
        validate: str,
    ) -> str:
        return await self.verification.verify(credential, challenge, validate)

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
            "x-rpc-device_id": self.device.device_id,
            "x-rpc-device_fp": self.device.device_fp,
            "X-Requested-With": "com.mihoyo.hyperion",
            "Content-Type": "application/json",
        }

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError(
                "mihoyo_error",
                MihoyoAPI._error_message(payload),
                502,
                {"retcode": str(payload.get("retcode", "unknown"))},
            )
        data: dict[str, Any] = payload.get("data") or {}
        return data

    @staticmethod
    def _error_message(payload: dict[str, Any]) -> str:
        retcode = payload.get("retcode")
        message = payload.get("message")
        if retcode in {-100, 10001}:
            return "米游社登录已失效，请退出账号后重新扫码登录"
        if retcode in {-10102, 10102}:
            return "请先在米游社中公开实时便笺数据"
        if retcode == 5003:
            return "米游社设备验证失败，请退出账号后重新扫码登录"
        if isinstance(message, str):
            normalized = message.strip()
            if normalized and not normalized.lstrip("-").isdigit():
                return normalized
        return f"米游社请求失败（错误码 {retcode if retcode is not None else '未知'}）"
