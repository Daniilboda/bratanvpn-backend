from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient

from app.services.vpn_agent_client import VpnAgentError
from tests.conftest import create_key_via_api


@pytest.mark.asyncio
async def test_activate_unknown_key(
    client: AsyncClient,
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    response = await client.post(
        "/api/v1/activate",
        json={
            "access_key": "BRATAN-DOESNOTEXIST0000",
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_activate_device_mismatch(
    client: AsyncClient,
    admin_headers: dict[str, str],
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    access_key = await create_key_via_api(client, admin_headers)

    first = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert first.status_code == 200

    second = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": "other-device",
            "vpn_public_key": "OTHERPUBLICKEYAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        },
    )
    assert second.status_code == 403
    assert "another device" in second.json()["detail"].lower()

    validate = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": "other-device"},
    )
    assert validate.status_code == 200
    assert validate.json()["status"] == "device_mismatch"

    config = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": "other-device"},
    )
    assert config.status_code == 403


@pytest.mark.asyncio
async def test_activate_rolls_back_when_vpn_agent_fails(
    client: AsyncClient,
    admin_headers: dict[str, str],
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    access_key = await create_key_via_api(client, admin_headers)

    with patch(
        "app.services.activation_service.add_peer_async",
        new=AsyncMock(side_effect=VpnAgentError("agent down")),
    ):
        response = await client.post(
            "/api/v1/activate",
            json={
                "access_key": access_key,
                "device_id": sample_device_id,
                "vpn_public_key": sample_vpn_public_key,
            },
        )

    assert response.status_code == 502

    # Key must stay creatable / not stuck activated.
    validate = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": sample_device_id},
    )
    assert validate.json()["status"] == "ready_to_activate"

    # Second attempt with working agent succeeds.
    retry = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert retry.status_code == 200


@pytest.mark.asyncio
async def test_revoke_fails_when_vpn_agent_fails(
    client: AsyncClient,
    admin_headers: dict[str, str],
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    access_key = await create_key_via_api(client, admin_headers)
    activate = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert activate.status_code == 200

    with patch(
        "app.services.access_key_service.remove_peer_async",
        new=AsyncMock(side_effect=VpnAgentError("agent down")),
    ):
        response = await client.patch(
            "/api/v1/admin/keys/revoke",
            headers=admin_headers,
            json={"key": access_key},
        )

    assert response.status_code == 502

    # Still activated — revoke did not commit.
    validate = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": sample_device_id},
    )
    assert validate.json()["status"] == "valid"


@pytest.mark.asyncio
async def test_validate_not_found(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/validate",
        json={"key": "BRATAN-MISSING00000000", "device_id": "x"},
    )
    assert response.status_code == 200
    assert response.json()["status"] == "not_found"


@pytest.mark.asyncio
async def test_vpn_config_not_found(client: AsyncClient) -> None:
    response = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": "BRATAN-MISSING00000000", "device_id": "x"},
    )
    assert response.status_code == 404
