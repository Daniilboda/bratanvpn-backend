"""VPN session lifecycle: allocate IP + peer on connect, clear on disconnect.

Still 1 access key = 1 device. vpn_ip is only set while the session is active.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.access_key import AccessKey
from app.services.vpn_agent_client import VpnAgentError, add_peer_async, remove_peer_async
from app.services.vpn_service import allocate_ip


async def connect_vpn_session(
    session: AsyncSession,
    access_key: str,
    device_id: str,
) -> str | dict:
    query = select(AccessKey).where(AccessKey.key == access_key)
    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status != "activated":
        return "not_activated"

    if key_from_db.device_id != device_id:
        return "device_mismatch"

    if key_from_db.vpn_public_key is None:
        return "missing_public_key"

    # Idempotent: already provisioned for an active session.
    if key_from_db.vpn_ip is not None:
        return {
            "status": "connected",
            "vpn_ip": key_from_db.vpn_ip,
        }

    vpn_ip = await allocate_ip(session)
    key_from_db.vpn_ip = vpn_ip

    try:
        await add_peer_async(key_from_db.vpn_public_key, vpn_ip)
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
    query = select(AccessKey).where(AccessKey.key == access_key)
    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status != "activated":
        return "not_activated"

    if key_from_db.device_id != device_id:
        return "device_mismatch"

    public_key = key_from_db.vpn_public_key
    had_session = key_from_db.vpn_ip is not None

    if had_session and public_key is not None:
        try:
            await remove_peer_async(public_key)
        except VpnAgentError:
            return "vpn_agent_failed"

    key_from_db.vpn_ip = None
    await session.commit()

    return {
        "status": "disconnected",
    }
