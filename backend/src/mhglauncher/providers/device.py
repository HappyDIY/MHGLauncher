from __future__ import annotations

import json
import os
import secrets
import time
import uuid
from pathlib import Path
from typing import Any

import httpx

from mhglauncher.errors import AppError

DEVICE_FP_URL = "https://public-data-api.mihoyo.com/device-fp/api/getFp"
PROFILE_VERSION = "android-v1"


class DeviceIdentity:
    def __init__(self, path: Path) -> None:
        self.path = path
        saved = self._load()
        self.device_id = str(saved.get("device_id") or uuid.uuid4())
        self.fp_device_id = str(saved.get("fp_device_id") or secrets.token_hex(8))
        self.device_name = str(saved.get("device_name") or self._random_text(12))
        self.product_name = str(saved.get("product_name") or self._random_text(6))
        self.device_fp = (
            str(saved.get("device_fp") or "")
            if saved.get("profile") == PROFILE_VERSION
            else ""
        )
        if not self.device_fp:
            self._save()

    async def ensure_fingerprint(self, client: httpx.AsyncClient) -> str:
        if self.device_fp:
            return self.device_fp
        response = await client.post(DEVICE_FP_URL, json=self._payload())
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        data = payload.get("data") or {}
        fingerprint = str(data.get("device_fp") or "")
        if payload.get("retcode") != 0 or not fingerprint:
            raise AppError("device_fp_failed", "米游社设备注册失败，请稍后重试", 502)
        self.device_fp = fingerprint
        self._save()
        return fingerprint

    def _payload(self) -> dict[str, str]:
        return {
            "device_id": self.fp_device_id,
            "seed_id": str(uuid.uuid4()),
            "seed_time": str(int(time.time() * 1000)),
            "platform": "2",
            "device_fp": secrets.token_hex(7)[:13],
            "app_name": "bbs_cn",
            "bbs_device_id": self.device_id,
            "ext_fields": json.dumps(self._android_fields(), separators=(",", ":")),
        }

    def _android_fields(self) -> dict[str, str | int]:
        return {
            "proxyStatus": 0,
            "isRoot": 0,
            "romCapacity": "512",
            "deviceName": self.device_name,
            "productName": self.product_name,
            "romRemain": "459",
            "manufacturer": "XiaoMi",
            "appMemory": "512",
            "hostname": "android-build",
            "screenSize": "1440x2905",
            "osVersion": "14",
            "aaid": "",
            "vendor": "unknown",
            "accelerometer": "1.48x7.17x6.28",
            "buildTags": "release-keys",
            "packageName": "com.mihoyo.hyperion",
            "networkType": "WiFi",
            "model": self.device_name,
            "brand": "XiaoMi",
            "oaid": "",
            "hardware": "qcom",
            "deviceType": "OP5913L1",
            "devId": "REL",
            "serialNumber": "unknown",
            "buildTime": "1693626947000",
            "buildUser": "android-build",
            "ramCapacity": "469679",
            "magnetometer": "20.08x-27.48x2.19",
            "display": f"{self.product_name}_14_release-keys",
            "ramRemain": "239814",
            "deviceInfo": (
                f"XiaoMi/{self.product_name}/OP5913L1:14/"
                "SKQ1.221119.001/release-keys"
            ),
            "gyroscope": "0.03x0.01x0.01",
            "vaid": "",
            "buildType": "user",
            "sdkVersion": "34",
            "board": "taro",
        }

    @staticmethod
    def _random_text(length: int) -> str:
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return "".join(secrets.choice(alphabet) for _ in range(length))

    def _load(self) -> dict[str, Any]:
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            return {}

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "profile": PROFILE_VERSION,
                    "device_id": self.device_id,
                    "fp_device_id": self.fp_device_id,
                    "device_name": self.device_name,
                    "product_name": self.product_name,
                    "device_fp": self.device_fp,
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        os.chmod(temporary, 0o600)
        temporary.replace(self.path)
