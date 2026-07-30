from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import settings
from app.db.base import Base
from app.db.session import get_db
from app.main import app


@pytest.fixture
async def db_engine() -> AsyncIterator[AsyncEngine]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session_factory(
    db_engine: AsyncEngine,
) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(
        bind=db_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )


@pytest.fixture
def admin_headers() -> dict[str, str]:
    return {"X-Admin-Key": settings.admin_api_key}


@pytest.fixture
async def client(
    session_factory: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncClient]:
    async def override_get_db() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db

    with (
        patch(
            "app.services.vpn_session_service.add_peer_async",
            new_callable=AsyncMock,
        ) as add_peer,
        patch(
            "app.services.vpn_session_service.remove_peer_async",
            new_callable=AsyncMock,
        ) as remove_peer_session,
        patch(
            "app.services.access_key_service.remove_peer_async",
            new_callable=AsyncMock,
        ) as remove_peer_revoke,
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            # Attach mocks for assertions in tests.
            ac.add_peer_mock = add_peer  # type: ignore[attr-defined]
            ac.remove_peer_mock = remove_peer_revoke  # type: ignore[attr-defined]
            ac.remove_peer_session_mock = remove_peer_session  # type: ignore[attr-defined]
            yield ac

    app.dependency_overrides.clear()


@pytest.fixture
def sample_vpn_public_key() -> str:
    return "TESTPUBLICKEYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


@pytest.fixture
def sample_device_id() -> str:
    return "device-test-001"


async def create_key_via_api(
    client: AsyncClient,
    admin_headers: dict[str, str],
) -> str:
    response = await client.post("/api/v1/admin/keys", headers=admin_headers)
    assert response.status_code == 200
    body: dict[str, Any] = response.json()
    assert body["status"] == "created"
    assert isinstance(body["key"], str)
    assert body["key"].startswith("BRATAN-")
    return body["key"]
