from __future__ import annotations

import asyncio

import httpx


async def _login(client: httpx.AsyncClient) -> str:
    created = (await client.post("/v1/auth/qr-sessions")).json()
    await client.get(f"/v1/auth/qr-sessions/{created['id']}")
    confirmed = (await client.get(f"/v1/auth/qr-sessions/{created['id']}")).json()
    identity = confirmed["identity"]
    await client.post(
        "/v1/auth/complete",
        json={"identity": identity, "credential_ref": "keychain:test"},
    )
    return identity["credential"]


async def _wait_for_wish_task(
    client: httpx.AsyncClient,
    task_id: str,
) -> dict:
    for _ in range(100):
        payload = (await client.get(f"/v1/wishes/tasks/{task_id}")).json()
        if payload["status"] in {"completed", "failed"}:
            return payload
        await asyncio.sleep(0)
    raise AssertionError("wish task did not finish")


async def test_wish_sync_task_reports_backend_events(
    api_client: httpx.AsyncClient,
) -> None:
    credential = await _login(api_client)
    started = await api_client.post(
        "/v1/wishes/tasks/sync",
        json={"credential": credential},
    )
    task = await _wait_for_wish_task(api_client, started.json()["id"])
    messages = [entry["message"] for entry in task["logs"]]

    assert started.status_code == 202
    assert task["status"] == "completed"
    assert task["progress"] == 1
    assert task["result"] == {"inserted": 2}
    assert any("第 1 页读取 2 条记录" in message for message in messages)
    assert all("任务仍在运行" not in message for message in messages)


async def test_invalid_uigf_task_exposes_real_error(
    api_client: httpx.AsyncClient,
) -> None:
    started = await api_client.post("/v1/wishes/tasks/import", json={"info": {}})
    task = await _wait_for_wish_task(api_client, started.json()["id"])

    assert task["status"] == "failed"
    assert task["progress"] is None
    assert "UIGF" in task["error"]
    assert task["logs"][-1]["message"] == task["error"]


async def test_wish_sync_is_idempotent(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    first = await api_client.post("/v1/wishes/sync", json={"credential": credential})
    second = await api_client.post("/v1/wishes/sync", json={"credential": credential})
    assert first.json()["inserted"] == 2
    assert second.json()["inserted"] == 0
    stats = (await api_client.get("/v1/wishes/statistics", params={"uid": "100000001"})).json()
    assert stats[0]["total"] == 2
    assert stats[0]["five_star_count"] == 1


async def test_uigf_export_and_reimport(api_client: httpx.AsyncClient) -> None:
    credential = await _login(api_client)
    await api_client.post("/v1/wishes/sync", json={"credential": credential})
    exported = (await api_client.get("/v1/wishes/export", params={"uid": "100000001"})).json()
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
