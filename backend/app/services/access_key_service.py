import secrets

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.access_key import AccessKey
from app.models.enums import AccessKeyStatus
from app.services.vpn_agent_client import VpnAgentError, remove_peer_async


def generate_access_key() -> str:
    random_part = secrets.token_hex(8).upper()

    return f"BRATAN-{random_part}"


async def create_access_key(
    session: AsyncSession,
) -> AccessKey:
    new_access_key = AccessKey(
        key=generate_access_key(),
        status=AccessKeyStatus.CREATED,
    )

    session.add(new_access_key)
    await session.commit()
    await session.refresh(new_access_key)

    return new_access_key



async def validate_access_key(
    session: AsyncSession,
    key: str,
    device_id: str,
) -> str:
    query = select(AccessKey).where(
        AccessKey.key == key
    )

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == AccessKeyStatus.REVOKED:
        return "revoked"

    if key_from_db.status == AccessKeyStatus.CREATED:
        return "ready_to_activate"

    if key_from_db.device_id != device_id:
        return "device_mismatch"

    return "valid"




async def revoke_access_key(
    session: AsyncSession,
    key: str,
) -> str:
    query = select(AccessKey).where(
        AccessKey.key == key
    )

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == AccessKeyStatus.REVOKED:
        return "already_revoked"

    public_key = key_from_db.vpn_public_key

    if public_key is not None:
        try:
            await remove_peer_async(public_key)
        except VpnAgentError:
            return "vpn_agent_failed"

    key_from_db.status = "revoked"
    key_from_db.vpn_ip = None
    key_from_db.vpn_public_key = None
    key_from_db.device_id = None

    await session.commit()
    await session.refresh(key_from_db)

    return "revoked"




async def restore_access_key(
    session: AsyncSession,
    key: str,
) -> str:
    query = select(AccessKey).where(
        AccessKey.key == key
    )

    result = await session.execute(query)
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status != AccessKeyStatus.REVOKED:
        return "not_revoked"

    if key_from_db.device_id is not None:
        key_from_db.status = AccessKeyStatus.ACTIVATED
        new_status = "restored_to_activated"
    else:
        key_from_db.status = AccessKeyStatus.CREATED
        new_status = "restored_to_created"

    await session.commit()
    await session.refresh(key_from_db)

    return new_status



async def get_access_keys(
    session: AsyncSession,
    status: str | None = None,
) -> list[AccessKey]:
    query = select(AccessKey).order_by(AccessKey.id)

    if status is not None:
        query = query.where(
            AccessKey.status == status
        )

    result = await session.execute(query)

    return list(result.scalars().all())


async def get_access_key(
    session: AsyncSession,
    key: str,
) -> AccessKey | None:
    query = select(AccessKey).where(
        AccessKey.key == key
    )

    result = await session.execute(query)

    return result.scalar_one_or_none()