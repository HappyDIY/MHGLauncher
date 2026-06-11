from __future__ import annotations

from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import urlencode
from uuid import uuid4

import httpx

from mhglauncher.errors import AppError
from mhglauncher.models import DailyNote, GameRole, QRSession, QRStatus, WishRecord
from mhglauncher.providers.base import AccountIdentity, GameBuild, PackageSegment
from mhglauncher.providers.mihoyo import MihoyoAPI


class LiveProvider:
    QR_CREATE = "https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin"
    QR_QUERY = "https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus"
    PACKAGES = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages"

    def __init__(self, client: httpx.AsyncClient) -> None:
        self.client = client
        self.device_id = str(uuid4())
        self.api = MihoyoAPI(client, self.device_id)
        self.sessions: dict[str, QRSession] = {}

    async def create_qr_session(self) -> QRSession:
        response = await self.client.post(
            self.QR_CREATE,
            headers={"x-rpc-device_id": self.device_id},
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
            headers={"x-rpc-device_id": self.device_id},
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
        del installed_version
        params = {"game_ids[]": "1Z8W5NHUQb", "launcher_id": "VYTpXlbWo8"}
        response = await self.client.get(f"{self.PACKAGES}?{urlencode(params)}")
        data = self._data(response)
        package = data["game_packages"][0]["main"]["major"]
        segments = [
            PackageSegment(
                url=item["url"],
                md5=item["md5"],
                size=item["size"],
                filename=item["url"].rsplit("/", 1)[-1],
            )
            for item in package["game_pkgs"] + package.get("audio_pkgs", [])
        ]
        return GameBuild(version=package["version"], segments=segments)

    async def iter_wishes(
        self,
        credential: str,
        role: GameRole,
        end_id: str = "0",
    ) -> AsyncIterator[list[WishRecord]]:
        async for page in self.api.wishes(credential, role, end_id):
            yield page

    async def get_daily_note(self, credential: str, role: GameRole) -> DailyNote:
        return await self.api.note(credential, role)

    @staticmethod
    def _data(response: httpx.Response) -> dict[str, Any]:
        response.raise_for_status()
        payload = response.json()
        if payload.get("retcode", 0) != 0:
            raise AppError("mihoyo_error", payload.get("message", "米游社请求失败"), 502)
        data: dict[str, Any] = payload["data"]
        return data

    @staticmethod
    def _qr_status(value: str) -> QRStatus:
        if value in {"confirmed", "3"}:
            return QRStatus.CONFIRMED
        if value in {"scanned", "2"}:
            return QRStatus.SCANNED
        if value in {"expired", "4"}:
            return QRStatus.EXPIRED
        return QRStatus.CREATED

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
        credential = f"stuid={aid}; stoken={stoken}; mid={mid}"
        return AccountIdentity(
            aid=aid,
            mid=mid,
            nickname=str(user.get("account_name", "米游社用户")),
            credential=credential,
        )
