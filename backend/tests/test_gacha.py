from __future__ import annotations

import httpx

from mhglauncher.models import GameRole
from mhglauncher.providers.gacha import GachaLogClient


def _role() -> GameRole:
    return GameRole(
        uid="10001",
        nickname="旅行者",
        region="cn_gf01",
        level=60,
        selected=True,
    )


async def test_incremental_sync_stops_at_newest_record() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        gacha_type = request.url.params["gacha_type"]
        items = []
        if gacha_type == "200":
            items = [
                _item("102", "新记录"),
                _item("101", "已有记录"),
                _item("100", "旧记录"),
            ]
        return httpx.Response(200, json={"retcode": 0, "data": {"list": items}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        gacha = GachaLogClient(client, delay=False)
        pages = [
            page
            async for page in gacha.pages("authkey", _role(), {"200": "101"})
        ]

    assert [[item.id for item in page] for page in pages] == [["102"]]
    assert len(requests) == 4


async def test_rate_limit_is_retried() -> None:
    attempts = 0

    def handler(_: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            return httpx.Response(
                200,
                json={"retcode": -1, "message": "visit too frequently"},
            )
        return httpx.Response(200, json={"retcode": 0, "data": {"list": []}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        gacha = GachaLogClient(client, delay=False)
        pages = [page async for page in gacha.pages("authkey", _role(), {})]

    assert pages == []
    assert attempts == 6


async def test_request_timeout_is_retried() -> None:
    attempts = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise httpx.ReadTimeout("timeout", request=request)
        return httpx.Response(200, json={"retcode": 0, "data": {"list": []}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        gacha = GachaLogClient(client, delay=False)
        pages = [page async for page in gacha.pages("authkey", _role(), {})]

    assert pages == []
    assert attempts == 6


def _item(identifier: str, name: str) -> dict[str, str]:
    return {
        "id": identifier,
        "gacha_type": "200",
        "item_id": "",
        "name": name,
        "item_type": "武器",
        "rank_type": "3",
        "time": "2026-06-11 08:00:00",
    }
