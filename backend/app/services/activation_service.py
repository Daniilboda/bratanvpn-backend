from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.enums import AccessKeyStatus
from app.services.vpn_service import allocate_ip
from app.models.access_key import AccessKey


async def activate_access_key(
    session: AsyncSession,
    access_key: str,
    device_id: str,
    vpn_public_key: str,
) -> str:
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

    await session.commit()


    return {
    "status": "activated",
    "vpn_ip": key_from_db.vpn_ip,
}