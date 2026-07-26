from __future__ import annotations

from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.db.session import get_db
from app.main import app
from app.services import health_service


class _FakeSession:
    async def execute(self, _statement: Any) -> None:
        return None


async def _override_get_db():
    yield _FakeSession()


@pytest.fixture(autouse=True)
def _override_db() -> None:
    app.dependency_overrides[get_db] = _override_get_db
    yield
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def _reset_alert_state() -> None:
    health_service._last_alert_signature = None
    health_service._last_alert_at = 0.0
    health_service._was_degraded = False


@pytest.mark.asyncio
async def test_health_all_ok() -> None:
    with (
        patch(
            "app.services.health_service.agent_status_async",
            new=AsyncMock(return_value="OK"),
        ),
        patch(
            "app.services.health_service.check_vps_internet_async",
            new=AsyncMock(return_value="ok"),
        ),
        patch(
            "app.services.health_service.check_disk_free_mb",
            return_value=4096,
        ),
        patch(
            "app.api.health.maybe_notify_health",
            new_callable=AsyncMock,
        ) as notify,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["api"] == "ok"
    assert body["database"] == "ok"
    assert body["vpn"] == "ok"
    assert body["internet"] == "ok"
    assert body["disk"] == "ok"
    assert body["disk_free_mb"] == 4096
    notify.assert_awaited_once()
    assert "password" not in response.text.lower()


@pytest.mark.asyncio
async def test_health_degraded_when_vpn_fails() -> None:
    from app.services.vpn_agent_client import VpnAgentError

    with (
        patch(
            "app.services.health_service.agent_status_async",
            new=AsyncMock(side_effect=VpnAgentError("down")),
        ),
        patch(
            "app.services.health_service.check_vps_internet_async",
            new=AsyncMock(return_value="ok"),
        ),
        patch(
            "app.services.health_service.check_disk_free_mb",
            return_value=1024,
        ),
        patch(
            "app.api.health.maybe_notify_health",
            new_callable=AsyncMock,
        ) as notify,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "degraded"
    assert body["vpn"] == "error"
    assert body["disk"] == "ok"
    notify.assert_awaited_once()


@pytest.mark.asyncio
async def test_maybe_notify_sends_on_degraded() -> None:
    report = {
        "status": "degraded",
        "database": "ok",
        "vpn": "error",
        "internet": "ok",
        "disk": "ok",
        "disk_free_mb": 1000,
    }
    with (
        patch("app.services.health_service.telegram_configured", return_value=True),
        patch(
            "app.services.health_service.send_telegram_message",
            new_callable=AsyncMock,
        ) as send,
    ):
        await health_service.maybe_notify_health(report)
        await health_service.maybe_notify_health(report)

    assert send.await_count == 1
    text = send.await_args.args[0]
    assert "проблемы" in text
    assert "vpn: error" in text


@pytest.mark.asyncio
async def test_maybe_notify_sends_recovery() -> None:
    degraded = {
        "status": "degraded",
        "database": "error",
        "vpn": "ok",
        "internet": "ok",
        "disk": "ok",
        "disk_free_mb": 1000,
    }
    ok = {
        "status": "ok",
        "database": "ok",
        "vpn": "ok",
        "internet": "ok",
        "disk": "ok",
        "disk_free_mb": 1000,
    }
    with (
        patch("app.services.health_service.telegram_configured", return_value=True),
        patch(
            "app.services.health_service.send_telegram_message",
            new_callable=AsyncMock,
        ) as send,
    ):
        await health_service.maybe_notify_health(degraded)
        await health_service.maybe_notify_health(ok)

    assert send.await_count == 2
    assert "норме" in send.await_args.args[0]
