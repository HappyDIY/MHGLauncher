from __future__ import annotations

import httpx

from mhglauncher.models import GameRole
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


async def test_roles_and_note_are_parsed() -> None:
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
        api = MihoyoAPI(client, "device")
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

