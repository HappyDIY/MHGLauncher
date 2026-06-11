from __future__ import annotations

import json
from pathlib import Path

import httpx

from mhglauncher.providers.device import DEVICE_FP_URL, DeviceIdentity


async def test_registers_and_persists_device_fingerprint(tmp_path: Path) -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "retcode": 0,
                "message": "OK",
                "data": {"device_fp": "38d8195157c8b", "code": 200},
            },
        )

    path = tmp_path / "device.json"
    device = DeviceIdentity(path)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        fingerprint = await device.ensure_fingerprint(client)

    assert fingerprint == "38d8195157c8b"
    assert str(requests[0].url) == DEVICE_FP_URL
    body = json.loads(requests[0].content)
    assert body["device_id"] == device.fp_device_id
    assert body["bbs_device_id"] == device.device_id
    assert body["platform"] == "2"
    assert json.loads(body["ext_fields"])["packageName"] == "com.mihoyo.hyperion"

    restored = DeviceIdentity(path)
    assert restored.device_id == device.device_id
    assert restored.device_fp == fingerprint
