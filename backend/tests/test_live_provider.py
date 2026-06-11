from __future__ import annotations

from pathlib import Path

import httpx
import pytest

from mhglauncher.errors import AppError
from mhglauncher.models import GameRole
from mhglauncher.providers.device import DeviceIdentity
from mhglauncher.providers.live import LiveProvider
from mhglauncher.providers.mihoyo import MihoyoAPI


def test_qr_identity_uses_stoken_token_type() -> None:
    identity = LiveProvider._identity(
        {
            "user_info": {
                "aid": "123",
                "mid": "mid-123",
                "account_name": "旅行者",
            },
            "tokens": [
                {"token_type": 2, "token": "other"},
                {"token_type": 1, "token": "secret"},
            ],
        }
    )
    assert identity.aid == "123"
    assert "stoken=secret" in identity.credential


def test_qr_identity_falls_back_for_empty_nickname() -> None:
    identity = LiveProvider._identity(
        {
            "user_info": {
                "aid": "123",
                "mid": "mid-123",
                "account_name": "",
            },
            "tokens": [{"token_type": 1, "token": "secret"}],
        }
    )
    assert identity.nickname == "米游社用户"


def test_numeric_upstream_message_is_readable() -> None:
    assert LiveProvider._error_message({"retcode": -1, "message": 2}) == (
        "米游社请求失败（错误码 -1）"
    )
    assert MihoyoAPI._error_message({"retcode": 10102, "message": 2}) == (
        "请先在米游社中公开实时便笺数据"
    )
    assert MihoyoAPI._error_message({"retcode": 5003, "message": 2}) == (
        "米游社设备验证失败，请退出账号后重新扫码登录"
    )


async def test_roles_and_note_are_parsed(tmp_path: Path) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if "getUserGameRolesByStoken" in str(request.url):
            return httpx.Response(
                200,
                json={
                    "retcode": 0,
                    "data": {
                        "list": [
                            {
                                "game_biz": "hk4e_cn",
                                "game_uid": "10001",
                                "nickname": "旅行者",
                                "region": "cn_gf01",
                                "level": 60,
                                "is_chosen": True,
                            }
                        ]
                    },
                },
            )
        if "/index" in str(request.url):
            return httpx.Response(200, json={"retcode": 0, "data": {}})
        return httpx.Response(
            200,
            json={
                "retcode": 0,
                "data": {
                    "current_resin": 80,
                    "max_resin": 200,
                    "finished_task_num": 4,
                    "total_task_num": 4,
                    "max_expedition_num": 5,
                    "expeditions": [{"status": "Finished"}],
                    "current_home_coin": 100,
                    "max_home_coin": 2400,
                    "remain_resin_discount_num": 2,
                    "transformer": {"recovery_time": {"reached": True}},
                },
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        device = DeviceIdentity(tmp_path / "device.json")
        device.device_fp = "fingerprint"
        api = MihoyoAPI(client, device)
        roles = await api.roles("stuid=1; stoken=token; mid=mid")
        note = await api.note("cookie_token=token; account_id=1", roles[0])
    assert roles == [
        GameRole(
            uid="10001",
            nickname="旅行者",
            region="cn_gf01",
            level=60,
            selected=True,
        )
    ]
    assert note.current_resin == 80
    assert note.transformer_ready is True


async def test_note_verification_flow(tmp_path: Path) -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        url = str(request.url)
        if "/index" in url:
            return httpx.Response(200, json={"retcode": 1034, "data": None})
        if "/dailyNote" in url:
            return httpx.Response(200, json={"retcode": 1034, "data": None})
        if "createVerification" in url:
            return httpx.Response(
                200,
                json={"retcode": 0, "data": {"gt": "gt-value", "challenge": "first"}},
            )
        return httpx.Response(
            200,
            json={"retcode": 0, "data": {"challenge": "verified-token"}},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        device = DeviceIdentity(tmp_path / "device.json")
        device.device_fp = "fingerprint"
        api = MihoyoAPI(client, device)
        role = GameRole(
            uid="10001",
            nickname="旅行者",
            region="cn_gf01",
            level=60,
            selected=True,
        )
        with pytest.raises(AppError) as caught:
            await api.note("cookie_token=token; account_id=1", role)
        token = await api.verify_challenge(
            "cookie_token=token; account_id=1",
            "first",
            "validation",
        )

    assert caught.value.code == "verification_required"
    assert caught.value.details == {"gt": "gt-value", "challenge": "first"}
    assert token == "verified-token"
    verify_request = requests[-1]
    assert verify_request.headers["x-rpc-challenge_game"] == "2"
    assert verify_request.headers["x-rpc-device_fp"] == "fingerprint"
    assert verify_request.content == (
        b'{"geetest_challenge":"first","geetest_validate":"validation",'
        b'"geetest_seccode":"validation|jordan"}'
    )
