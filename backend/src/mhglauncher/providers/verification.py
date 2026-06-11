from __future__ import annotations

import json
from typing import Any

import httpx

from mhglauncher.errors import AppError
from mhglauncher.providers.device import DeviceIdentity
from mhglauncher.providers.signing import data_sign

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1"
BASE_URL = "https://api-takumi-record.mihoyo.com/game_record/app/card/wapi"
CHALLENGE_PATH = (
    "https://api-takumi-record.mihoyo.com/"
    "game_record/app/genshin/api/dailyNote"
)


class MihoyoVerification:
    def __init__(self, client: httpx.AsyncClient, device: DeviceIdentity) -> None:
        self.client = client
        self.device = device

    async def create(self, credential: str) -> dict[str, str]:
        query = "is_high=true"
        headers = self._headers(credential, query=query)
        response = await self.client.get(
            f"{BASE_URL}/createVerification?{query}",
            headers=headers,
        )
        data = self._data(response)
        return {"gt": str(data["gt"]), "challenge": str(data["challenge"])}

    async def verify(
        self,
        credential: str,
        challenge: str,
        validation: str,
    ) -> str:
        payload = {
            "geetest_challenge": challenge,
            "geetest_validate": validation,
            "geetest_seccode": f"{validation}|jordan",
        }
        body = json.dumps(payload, separators=(",", ":"))
        response = await self.client.post(
            f"{BASE_URL}/verifyVerification",
            content=body,
            headers=self._headers(credential, body=body),
        )
        return str(self._data(response)["challenge"])

    def _headers(
        self,
        credential: str,
        *,
        query: str = "",
        body: str = "",
    ) -> dict[str, str]:
        return {
            "Cookie": credential,
            "DS": data_sign("x4", query=query, body=body),
            "User-Agent": USER_AGENT,
            "x-rpc-app_version": "2.95.1",
            "x-rpc-client_type": "5",
            "x-rpc-device_id": self.device.device_id,
            "x-rpc-device_fp": self.device.device_fp,
            "x-rpc-challenge_game": "2",
            "x-rpc-challenge_path": CHALLENGE_PATH,
            "X-Requested-With": "com.mihoyo.hyperion",
            "Content-Type": "application/json",
            "Referer": "https://webstatic.mihoyo.com/",
        }

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError(
                "mihoyo_error",
                "米游社人机验证失败，请重新验证",
                502,
                {"retcode": str(payload.get("retcode", "unknown"))},
            )
        data: dict[str, Any] = payload.get("data") or {}
        return data
