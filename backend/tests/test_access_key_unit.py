from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.access_key import AccessKey
from app.models.device import Device
from app.models.vpn_session import VpnSession
from app.services.access_key_service import generate_access_key
from app.services.vpn_service import allocate_ip


def test_generate_access_key_format() -> None:
    key = generate_access_key()
    assert key.startswith("BRATAN-")
    suffix = key.removeprefix("BRATAN-")
    assert len(suffix) == 16
    assert suffix == suffix.upper()
    int(suffix, 16)  # hex


def test_generate_access_key_unique() -> None:
    keys = {generate_access_key() for _ in range(50)}
    assert len(keys) == 50


@pytest.mark.asyncio
async def test_allocate_ip_skips_gateway_and_used(
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    async with session_factory() as session:
        access_key = AccessKey(
            key="BRATAN-AAAAAAAAAAAAAAA1",
            status="activated",
        )
        session.add(access_key)
        await session.flush()
        device = Device(
            access_key_id=access_key.id,
            device_id="dev-allocate-ip-1",
            platform="windows",
            vpn_public_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        )
        session.add(device)
        await session.flush()
        session.add(
            VpnSession(
                access_key_id=access_key.id,
                device_id=device.id,
                vpn_ip="10.8.0.2",
            )
        )
        await session.commit()

        ip = await allocate_ip(session)
        assert ip == "10.8.0.3"
        assert ip != "10.8.0.1"
