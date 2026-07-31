"""VPN session lifecycle on devices + vpn_sessions (Multi Device canvas)."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.limits import MAX_ACTIVE_SESSIONS
from app.models.access_key import AccessKey
from app.models.device import Device
from app.models.vpn_session import VpnSession
from app.services.vpn_agent_client import VpnAgentError, add_peer_async, remove_peer_async
from app.services.vpn_service import allocate_ip


async def _get_key_with_devices(
    session: AsyncSession,
    access_key: str,
) -> AccessKey | None:
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == access_key)
        .options(selectinload(AccessKey.devices))
    )
    return result.scalar_one_or_none()


def _find_device(key: AccessKey, device_id: str) -> Device | None:
    for device in key.devices:
        if device.device_id == device_id:
            return device
    return None


async def _active_session(
    session: AsyncSession,
    device_pk: int,
) -> VpnSession | None:
    result = await session.execute(
        select(VpnSession).where(VpnSession.device_id == device_pk)
    )
    return result.scalar_one_or_none()


async def _count_sessions_for_key(
    session: AsyncSession,
    access_key_id: int,
) -> int:
    result = await session.execute(
        select(func.count())
        .select_from(VpnSession)
        .where(VpnSession.access_key_id == access_key_id)
    )
    return int(result.scalar_one())


async def connect_vpn_session(
    session: AsyncSession,
    access_key: str,
    device_id: str,
) -> str | dict:
    key_from_db = await _get_key_with_devices(session, access_key)

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status != "activated":
        return "not_activated"

    device = _find_device(key_from_db, device_id)
    if device is None:
        return "device_mismatch"

    existing = await _active_session(session, device.id)
    if existing is not None:
        return {
            "status": "connected",
            "vpn_ip": existing.vpn_ip,
        }

    slots = await _count_sessions_for_key(session, key_from_db.id)
    if slots >= MAX_ACTIVE_SESSIONS:
        return "session_limit"

    vpn_ip = await allocate_ip(session)
    session.add(
        VpnSession(
            access_key_id=key_from_db.id,
            device_id=device.id,
            vpn_ip=vpn_ip,
        )
    )

    try:
        await add_peer_async(device.vpn_public_key, vpn_ip)
    except VpnAgentError:
        await session.rollback()
        return "vpn_agent_failed"

    await session.commit()

    return {
        "status": "connected",
        "vpn_ip": vpn_ip,
    }


async def disconnect_vpn_session(
    session: AsyncSession,
    access_key: str,
    device_id: str,
) -> str | dict:
    key_from_db = await _get_key_with_devices(session, access_key)

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status != "activated":
        return "not_activated"

    device = _find_device(key_from_db, device_id)
    if device is None:
        return "device_mismatch"

    existing = await _active_session(session, device.id)
    if existing is None:
        return {"status": "disconnected"}

    try:
        await remove_peer_async(device.vpn_public_key)
    except VpnAgentError:
        return "vpn_agent_failed"

    await session.delete(existing)
    await session.commit()

    return {
        "status": "disconnected",
    }
