import secrets

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.access_key import AccessKey
from app.models.device import Device
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
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == key)
        .options(selectinload(AccessKey.devices))
    )
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == AccessKeyStatus.REVOKED:
        return "revoked"

    if key_from_db.status == AccessKeyStatus.CREATED:
        return "ready_to_activate"

    if not any(d.device_id == device_id for d in key_from_db.devices):
        # Key activated on other device(s), but this client is not bound yet.
        # Client may still call activate to bind — validate as ready_to_activate
        # only when no devices; otherwise device_mismatch keeps old UX for
        # unregistered device_id until it binds.
        return "device_mismatch"

    return "valid"


async def revoke_access_key(
    session: AsyncSession,
    key: str,
) -> str:
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == key)
        .options(
            selectinload(AccessKey.devices).selectinload(Device.sessions),
        )
    )
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == AccessKeyStatus.REVOKED:
        return "already_revoked"

    for device in key_from_db.devices:
        if device.sessions:
            try:
                await remove_peer_async(device.vpn_public_key)
            except VpnAgentError:
                return "vpn_agent_failed"
            for vpn_session in list(device.sessions):
                await session.delete(vpn_session)

    key_from_db.status = "revoked"
    await session.commit()
    await session.refresh(key_from_db)

    return "revoked"


async def restore_access_key(
    session: AsyncSession,
    key: str,
) -> str:
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == key)
        .options(selectinload(AccessKey.devices))
    )
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status != AccessKeyStatus.REVOKED:
        return "not_revoked"

    if key_from_db.devices:
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
