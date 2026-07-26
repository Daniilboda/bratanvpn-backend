from __future__ import annotations

import pytest
from httpx import AsyncClient

from tests.conftest import create_key_via_api


@pytest.mark.asyncio
async def test_admin_rejects_missing_key(client: AsyncClient) -> None:
    response = await client.post("/api/v1/admin/keys")
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_admin_rejects_wrong_key(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/admin/keys",
        headers={"X-Admin-Key": "definitely-wrong-key"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_admin_create_list_get_filter(
    client: AsyncClient,
    admin_headers: dict[str, str],
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    key_a = await create_key_via_api(client, admin_headers)
    key_b = await create_key_via_api(client, admin_headers)
    assert key_a != key_b

    activate = await client.post(
        "/api/v1/activate",
        json={
            "access_key": key_a,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert activate.status_code == 200

    all_keys = await client.get("/api/v1/admin/keys", headers=admin_headers)
    assert all_keys.status_code == 200
    keys = all_keys.json()
    assert len(keys) >= 2
    by_key = {item["key"]: item for item in keys}
    assert by_key[key_a]["status"] == "activated"
    assert by_key[key_a]["device_id"] == sample_device_id
    assert by_key[key_b]["status"] == "created"

    created_only = await client.get(
        "/api/v1/admin/keys",
        headers=admin_headers,
        params={"status": "created"},
    )
    assert created_only.status_code == 200
    created_keys = {item["key"] for item in created_only.json()}
    assert key_b in created_keys
    assert key_a not in created_keys

    one = await client.get(f"/api/v1/admin/keys/{key_a}", headers=admin_headers)
    assert one.status_code == 200
    assert one.json()["key"] == key_a
    assert one.json()["status"] == "activated"

    missing = await client.get(
        "/api/v1/admin/keys/BRATAN-NOSUCHKEY000000",
        headers=admin_headers,
    )
    assert missing.status_code == 200
    assert missing.json()["status"] == "not_found"


@pytest.mark.asyncio
async def test_revoke_unknown_and_already_revoked(
    client: AsyncClient,
    admin_headers: dict[str, str],
) -> None:
    missing = await client.patch(
        "/api/v1/admin/keys/revoke",
        headers=admin_headers,
        json={"key": "BRATAN-NOSUCHKEY000000"},
    )
    assert missing.status_code == 200
    assert missing.json()["status"] == "not_found"

    access_key = await create_key_via_api(client, admin_headers)
    first = await client.patch(
        "/api/v1/admin/keys/revoke",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert first.status_code == 200
    assert first.json()["status"] == "revoked"

    second = await client.patch(
        "/api/v1/admin/keys/revoke",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert second.status_code == 200
    assert second.json()["status"] == "already_revoked"


@pytest.mark.asyncio
async def test_restore_not_revoked(
    client: AsyncClient,
    admin_headers: dict[str, str],
) -> None:
    access_key = await create_key_via_api(client, admin_headers)
    response = await client.patch(
        "/api/v1/admin/keys/restore",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "not_revoked"
