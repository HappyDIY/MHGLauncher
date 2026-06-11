from __future__ import annotations

import hashlib
import random
import string
import time
from urllib.parse import parse_qsl, urlencode

SALTS = {
    "prod": "JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS",
    "x4": "xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs",
    "lk2": "sidQFEglajEz7FA0Aj7HQPV88zpf17SO",
}


def data_sign(kind: str, body: str = "", query: str = "", generation: int = 2) -> str:
    timestamp = int(time.time())
    alphabet = string.ascii_lowercase + string.digits
    random_value = "".join(random.choices(alphabet, k=6))
    content = f"salt={SALTS[kind]}&t={timestamp}&r={random_value}"
    if generation == 2:
        normalized = urlencode(sorted(parse_qsl(query, keep_blank_values=True)))
        content += f"&b={body}&q={normalized}"
    digest = hashlib.md5(content.encode(), usedforsecurity=False).hexdigest()
    return f"{timestamp},{random_value},{digest}"


def cookie_map(raw: str) -> dict[str, str]:
    result = {}
    for part in raw.split(";"):
        key, separator, value = part.strip().partition("=")
        if separator:
            result[key] = value
    return result

