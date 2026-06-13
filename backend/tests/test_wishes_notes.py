from __future__ import annotations

import httpx


async def _login(client: httpx.AsyncClient) -> str:
    created = (await client.post("/v1/auth/qr-sessions")).json()
    await client.get(f"/v1/auth/qr-sessions/{created['id']}")
    confirmed = (
        await client.get(f"/v1/auth/qr-sessions/{created['id']}")
    ).json()
    identity = confirmed["identity"]
    await client.post(
        "/v1/auth/complete",
        json={"identity": identity, "credential_ref": "keychain:test"},
    )
    return identity["credential"]


async def test_wish_sync_is_idempotent(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    first = await api_client.post("/v1/wishes/sync", json={"credential": credential})
    second = await api_client.post("/v1/wishes/sync", json={"credential": credential})
    assert first.json()["inserted"] == 2
    assert second.json()["inserted"] == 0
    stats = (
        await api_client.get("/v1/wishes/statistics", params={"uid": "100000001"})
    ).json()
    assert stats[0]["total"] == 2
    assert stats[0]["five_star_count"] == 1


async def test_uigf_export_and_reimport(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    await api_client.post("/v1/wishes/sync", json={"credential": credential})
    exported = (
        await api_client.get("/v1/wishes/export", params={"uid": "100000001"})
    ).json()
    assert exported["info"]["version"] == "v4.2"
    assert "uigf_version" not in exported["info"]
    imported = await api_client.post("/v1/wishes/import", json=exported)
    assert imported.json()["imported"] == 2


async def test_clear_all_wishes(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    await api_client.post("/v1/wishes/sync", json={"credential": credential})
    cleared = await api_client.delete("/v1/wishes")
    records = await api_client.get("/v1/wishes", params={"uid": "100000001"})
    assert cleared.json()["deleted"] == 2
    assert records.json() == []


async def test_note_refresh_and_cache(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    refreshed = await api_client.post(
        "/v1/notes/refresh",
        json={"credential": credential},
    )
    assert refreshed.json()["current_resin"] == 120
    cached = await api_client.get("/v1/notes", params={"uid": "100000001"})
    assert cached.json()["finished_tasks"] == 3
