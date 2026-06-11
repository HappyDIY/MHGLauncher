from __future__ import annotations

import hmac

from fastapi import Header, Request

from mhglauncher.errors import AppError


async def require_token(
    request: Request,
    authorization: str | None = Header(default=None),
) -> None:
    expected = request.app.state.settings.api_token
    if not expected:
        return
    actual = authorization.removeprefix("Bearer ") if authorization else ""
    if not hmac.compare_digest(actual, expected):
        raise AppError("unauthorized", "本地服务鉴权失败", 401)

