from __future__ import annotations

import time
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

from mhglauncher.errors import AppError
from mhglauncher.models import DailyNote, GameRole, QRSession, QRStatus, WishRecord
from mhglauncher.providers.base import AccountIdentity, GameBuild
from mhglauncher.providers.device import DeviceIdentity
from mhglauncher.providers.mihoyo import MihoyoAPI
from mhglauncher.providers.sophon import SophonAPI


class LiveProvider:
    QR_CREATE = "https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin"
    QR_QUERY = "https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus"
    def __init__(self, client: httpx.AsyncClient, device: DeviceIdentity) -> None:
        self.client = client
        self.device = device
        self.api = MihoyoAPI(client, device)
        self.sophon = SophonAPI(client)
        self.sessions: dict[str, QRSession] = {}
        self.build_cache: tuple[float, str, GameBuild] | None = None

    async def create_qr_session(self) -> QRSession:
        response = await self.client.post(
            self.QR_CREATE,
            headers=self._qr_headers(),
            json={},
        )
        data = self._data(response)
        session = QRSession(
            id=data["ticket"],
            url=data["url"],
            status=QRStatus.CREATED,
            expires_at=datetime.now(UTC) + timedelta(minutes=5),
        )
        self.sessions[session.id] = session
        return session

    async def query_qr_session(self, session_id: str) -> tuple[QRSession, AccountIdentity | None]:
        response = await self.client.post(
            self.QR_QUERY,
            headers=self._qr_headers(),
            json={"ticket": session_id},
        )
        data = self._data(response)
        raw_status = str(data.get("status", "")).lower()
        status = self._qr_status(raw_status)
        session = self.sessions.get(session_id)
        if session is None:
            raise AppError("qr_session_missing", "二维码会话不存在", 404)
        updated = session.model_copy(update={"status": status})
        identity = None
        if status is QRStatus.CONFIRMED:
            identity = self._identity(data)
            enriched = await self.api.enrich_credential(identity.credential)
            identity = identity.model_copy(update={"credential": enriched})
        return updated, identity

    async def get_roles(self, credential: str) -> list[GameRole]:
        return await self.api.roles(credential)

    async def get_build(self, installed_version: str = "") -> GameBuild:
        cached = self.build_cache
        if (
            cached is not None
            and cached[1] == installed_version
            and time.monotonic() - cached[0] < 300
        ):
            return cached[2]
        build = await self.sophon.build(installed_version)
        self.build_cache = (time.monotonic(), installed_version, build)
        return build

    async def iter_wishes(
        self,
        credential: str,
        role: GameRole,
        newest_ids: dict[str, str] | None = None,
    ) -> AsyncIterator[list[WishRecord]]:
        async for page in self.api.wishes(credential, role, newest_ids or {}):
            yield page

    async def get_daily_note(
        self,
        credential: str,
        role: GameRole,
        xrpc_challenge: str = "",
    ) -> DailyNote:
        return await self.api.note(credential, role, xrpc_challenge)

    async def verify_note_challenge(
        self,
        credential: str,
        challenge: str,
        validate: str,
    ) -> str:
        return await self.api.verify_challenge(credential, challenge, validate)

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError(
                "mihoyo_error",
                LiveProvider._error_message(payload),
                502,
                {"retcode": str(payload.get("retcode", "unknown"))},
            )
        data: dict[str, Any] = payload["data"]
        return data

    @staticmethod
    def _error_message(payload: dict[str, Any]) -> str:
        retcode = payload.get("retcode")
        message = payload.get("message")
        if isinstance(message, str):
            normalized = message.strip()
            if normalized and not normalized.lstrip("-").isdigit():
                return normalized
        return f"米游社请求失败（错误码 {retcode if retcode is not None else '未知'}）"

    @staticmethod
    def _qr_status(value: str) -> QRStatus:
        if value in {"confirmed", "3"}:
            return QRStatus.CONFIRMED
        if value in {"scanned", "2"}:
            return QRStatus.SCANNED
        if value in {"expired", "4"}:
            return QRStatus.EXPIRED
        return QRStatus.CREATED

    def _qr_headers(self) -> dict[str, str]:
        return {
            "User-Agent": "HYPContainer/1.1.4.133",
            "Accept": "application/json",
            "x-rpc-app_id": "ddxf5dufpuyo",
            "x-rpc-client_type": "3",
            "x-rpc-device_id": self.device.device_id,
        }

    @staticmethod
    def _identity(data: dict[str, Any]) -> AccountIdentity:
        user = data.get("user_info")
        tokens = data.get("tokens")
        if not isinstance(user, dict) or not isinstance(tokens, list):
            raise AppError("qr_payload_invalid", "二维码登录结果缺少凭据", 502)
        stoken = next(
            (str(item["token"]) for item in tokens if item.get("token_type") == 1),
            "",
        )
        aid = str(user.get("aid", ""))
        mid = str(user.get("mid", ""))
        nickname = str(user.get("account_name") or "").strip() or "米游社用户"
        credential = f"stuid={aid}; stoken={stoken}; mid={mid}"
        return AccountIdentity(
            aid=aid,
            mid=mid,
            nickname=nickname,
            credential=credential,
        )
