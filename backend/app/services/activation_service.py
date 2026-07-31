from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.access_key import AccessKey
from app.models.device import Device
from app.models.vpn_session import VpnSession


async def activate_access_key(
    session: AsyncSession,
    access_key: str,
    device_id: str,
    vpn_public_key: str,
) -> str | dict:
    """Bind access key to a device (multi-device). Does not allocate vpn_ip / peer."""
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == access_key)
        .options(
            selectinload(AccessKey.devices).selectinload(Device.sessions),
        )
    )
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    existing = next(
        (d for d in key_from_db.devices if d.device_id == device_id),
        None,
    )

    if existing is not None:
        if existing.vpn_public_key != vpn_public_key:
            if existing.sessions:
                return "session_active"
            existing.vpn_public_key = vpn_public_key
            await session.commit()
        return {"status": "activated"}

    # Another device may already be bound — that is allowed (multi-device).
    session.add(
        Device(
            access_key_id=key_from_db.id,
            device_id=device_id,
            vpn_public_key=vpn_public_key,
            platform=None,
        )
    )
    if key_from_db.status == "created":
        key_from_db.status = "activated"

    await session.commit()

    return {
        "status": "activated",
    }
