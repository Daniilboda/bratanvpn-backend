from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.enums import AccessKeyStatus

from app.models.access_key import AccessKey


async def activate_access_key(
    session: AsyncSession,
    access_key: str,
    device_id: str,
) -> str:
    query = select(AccessKey).where(
        AccessKey.key == access_key
    )

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "activated":
        if key_from_db.device_id == device_id:
            return "already_activated"

        return "device_mismatch"

    key_from_db.status = "activated"
    key_from_db.device_id = device_id

    await session.commit()

    return "activated"