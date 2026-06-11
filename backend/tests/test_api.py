from __future__ import annotations

import httpx


async def test_health_does_not_require_token(api_client: httpx.AsyncClient) -> None:
    response = await api_client.get("/health", headers={})
    assert response.json()["status"] == "ok"


async def test_api_rejects_invalid_token(api_client: httpx.AsyncClient) -> None:
    response = await api_client.get(
        "/v1/account",
        headers={"Authorization": "Bearer wrong"},
    )
    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"


async def test_qr_login_account_and_roles(api_client: httpx.AsyncClient) -> None:
    created = (await api_client.post("/v1/auth/qr-sessions")).json()
    first = (
        await api_client.get(f"/v1/auth/qr-sessions/{created['id']}")
    ).json()
    assert first["session"]["status"] == "scanned"
    confirmed = (
        await api_client.get(f"/v1/auth/qr-sessions/{created['id']}")
    ).json()
    assert confirmed["session"]["status"] == "confirmed"

    response = await api_client.post(
        "/v1/auth/complete",
        json={
            "identity": confirmed["identity"],
            "credential_ref": "keychain:test",
        },
    )
    assert response.status_code == 200
    assert response.json()["roles"][0]["uid"] == "100000001"
    account = (await api_client.get("/v1/account")).json()
    assert account["credential_ref"] == "keychain:test"


async def test_launch_is_explicit_placeholder(api_client: httpx.AsyncClient) -> None:
    response = await api_client.post("/v1/game/launch")
    assert response.status_code == 501
    assert response.json()["code"] == "launch_not_implemented"

