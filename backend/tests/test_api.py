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


async def test_game_status_detects_selected_path(
    api_client: httpx.AsyncClient,
    tmp_path,
) -> None:
    game = tmp_path / "Genshin Impact Game"
    game.mkdir()
    (game / "YuanShen.exe").write_bytes(b"")
    (game / "config.ini").write_text("[General]\ngame_version=5.7.0\n")
    response = await api_client.get(
        "/v1/game/status/path",
        params={"install_path": str(game)},
    )
    assert response.status_code == 200
    assert response.json()["installed_version"] == "5.7.0"
    assert response.json()["status"] == "update_available"
