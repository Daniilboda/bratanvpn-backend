from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.access_key import AccessKey


async def activate_access_key(
    session: AsyncSession,
    access_key: str,
    device_id: str,
    vpn_public_key: str,
) -> str | dict:
    """Bind access key to one device. Does not allocate vpn_ip or add AWG peer."""
    query = select(AccessKey).where(AccessKey.key == access_key)

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status == "activated":
        if key_from_db.device_id == device_id:
            # Idempotent re-bind; keep existing public key unless client sends a new one
            # for the same device (e.g. reinstall with same device_id — rare).
            if key_from_db.vpn_public_key != vpn_public_key:
                # Do not swap keys while a live session may exist.
                if key_from_db.vpn_ip is not None:
                    return "session_active"
                key_from_db.vpn_public_key = vpn_public_key
                await session.commit()
            return {
                "status": "activated",
            }

        return "device_mismatch"

    key_from_db.status = "activated"
    key_from_db.device_id = device_id
    key_from_db.vpn_public_key = vpn_public_key
    key_from_db.vpn_ip = None

    await session.commit()

    return {
        "status": "activated",
    }
