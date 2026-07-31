from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from tests.conftest import create_key_via_api


@pytest.mark.asyncio
async def test_critical_path_activate_connect_config_validate_revoke(
    client: AsyncClient,
    admin_headers: dict[str, str],
    sample_device_id: str,
    sample_vpn_public_key: str,
) -> None:
    """Happy path: create → activate → connect → config → validate → revoke."""
    access_key = await create_key_via_api(client, admin_headers)

    validate_before = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": sample_device_id},
    )
    assert validate_before.status_code == 200
    assert validate_before.json()["status"] == "ready_to_activate"

    config_before = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config_before.status_code == 403
    assert "not activated" in config_before.json()["detail"].lower()

    activate = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert activate.status_code == 200
    activate_body: dict[str, Any] = activate.json()
    assert activate_body["status"] == "activated"
    assert "vpn_ip" not in activate_body
    client.add_peer_mock.assert_not_awaited()  # type: ignore[attr-defined]

    # Bound but not connected → no vpn_ip yet.
    config_bound = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config_bound.status_code == 409
    assert "not provisioned" in config_bound.json()["detail"].lower()

    # Idempotent re-activate same device.
    activate_again = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert activate_again.status_code == 200
    assert activate_again.json()["status"] == "activated"

    connect = await client.post(
        "/api/v1/vpn/connect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert connect.status_code == 200
    connect_body: dict[str, Any] = connect.json()
    assert connect_body["vpn_ip"].startswith("10.8.0.")
    assert connect_body["vpn_ip"] != "10.8.0.1"
    client.add_peer_mock.assert_awaited_once_with(  # type: ignore[attr-defined]
        sample_vpn_public_key,
        connect_body["vpn_ip"],
    )

    # Idempotent connect keeps same IP.
    connect_again = await client.post(
        "/api/v1/vpn/connect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert connect_again.status_code == 200
    assert connect_again.json()["vpn_ip"] == connect_body["vpn_ip"]
    assert client.add_peer_mock.await_count == 1  # type: ignore[attr-defined]

    validate_ok = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": sample_device_id},
    )
    assert validate_ok.status_code == 200
    assert validate_ok.json()["status"] == "valid"

    config = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config.status_code == 200
    config_body: dict[str, Any] = config.json()
    assert config_body["schema_version"] == 1
    assert config_body["protocol"]["type"] == "amneziawg"
    assert config_body["client"]["vpn_ip"] == connect_body["vpn_ip"]
    assert "private_key" not in config.text.lower()
    assert "privatekey" not in config.text.lower()

    disconnect = await client.post(
        "/api/v1/vpn/disconnect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert disconnect.status_code == 200
    client.remove_peer_session_mock.assert_awaited_once_with(  # type: ignore[attr-defined]
        sample_vpn_public_key,
    )

    config_after_disconnect = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config_after_disconnect.status_code == 409

    # Connect again for revoke-with-peer path.
    reconnect = await client.post(
        "/api/v1/vpn/connect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert reconnect.status_code == 200
    reconnect_ip = reconnect.json()["vpn_ip"]

    revoke = await client.patch(
        "/api/v1/admin/keys/revoke",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert revoke.status_code == 200
    assert revoke.json()["status"] == "revoked"
    client.remove_peer_mock.assert_awaited_once_with(  # type: ignore[attr-defined]
        sample_vpn_public_key,
    )

    validate_revoked = await client.post(
        "/api/v1/validate",
        json={"key": access_key, "device_id": sample_device_id},
    )
    assert validate_revoked.status_code == 200
    assert validate_revoked.json()["status"] == "revoked"

    config_revoked = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config_revoked.status_code == 403
    assert "revoked" in config_revoked.json()["detail"].lower()

    activate_revoked = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": sample_vpn_public_key,
        },
    )
    assert activate_revoked.status_code == 403
    assert "revoked" in activate_revoked.json()["detail"].lower()
    assert reconnect_ip.startswith("10.8.0.")


@pytest.mark.asyncio
async def test_restore_then_activate_and_connect_again(
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

    connect = await client.post(
        "/api/v1/vpn/connect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert connect.status_code == 200
    first_ip = connect.json()["vpn_ip"]

    revoke = await client.patch(
        "/api/v1/admin/keys/revoke",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert revoke.status_code == 200

    restore = await client.patch(
        "/api/v1/admin/keys/restore",
        headers=admin_headers,
        json={"key": access_key},
    )
    assert restore.status_code == 200
    assert restore.json()["status"] == "restored_to_activated"

    new_pubkey = "TESTPUBLICKEYBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    activate2 = await client.post(
        "/api/v1/activate",
        json={
            "access_key": access_key,
            "device_id": sample_device_id,
            "vpn_public_key": new_pubkey,
        },
    )
    assert activate2.status_code == 200

    connect2 = await client.post(
        "/api/v1/vpn/connect",
        json={"access_key": access_key, "device_id": sample_device_id},
    )
    assert connect2.status_code == 200
    second_ip = connect2.json()["vpn_ip"]
    assert second_ip.startswith("10.8.0.")
    assert second_ip != "10.8.0.1"
    assert first_ip.startswith("10.8.0.")

    config = await client.get(
        "/api/v1/vpn/config",
        params={"access_key": access_key, "device_id": sample_device_id},
    )
    assert config.status_code == 200
    assert config.json()["client"]["vpn_ip"] == second_ip
