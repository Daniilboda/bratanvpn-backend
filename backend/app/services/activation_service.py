from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.access_key import AccessKey
from app.services.vpn_agent_client import VpnAgentError, add_peer_async
from app.services.vpn_service import allocate_ip


async def activate_access_key(
    session: AsyncSession,
    access_key: str,
    device_id: str,
    vpn_public_key: str,
) -> str | dict:
    query = select(AccessKey).where(
        AccessKey.key == access_key
    )

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status == "activated":
        if key_from_db.device_id == device_id:
            return {
                "status": "activated",
                "vpn_ip": key_from_db.vpn_ip,
            }

        return "device_mismatch"

    vpn_ip = await allocate_ip(session)

    key_from_db.status = "activated"
    key_from_db.device_id = device_id
    key_from_db.vpn_public_key = vpn_public_key
    key_from_db.vpn_ip = vpn_ip

    try:
        await add_peer_async(vpn_public_key, vpn_ip)
    except VpnAgentError:
        await session.rollback()
        return "vpn_agent_failed"

    await session.commit()

    return {
        "status": "activated",
        "vpn_ip": key_from_db.vpn_ip,
    }
