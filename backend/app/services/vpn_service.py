import ipaddress

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.access_key import AccessKey


async def allocate_ip(session: AsyncSession) -> str:
    query = select(AccessKey.vpn_ip).where(AccessKey.vpn_ip.is_not(None))

    result = await session.execute(query)

    used_ips = set(result.scalars().all())

    network = ipaddress.ip_network("10.8.0.0/24")

    for ip in network.hosts():
        ip_string = str(ip)

        if ip_string == "10.8.0.1":
            continue

        if ip_string not in used_ips:
            return ip_string

    raise RuntimeError("Свободные VPN-IP закончились")


async def assign_vpn_to_access_key(
    session: AsyncSession,
    access_key: AccessKey,
    public_key: str,
    vpn_ip: str,
) -> AccessKey:
    access_key.vpn_public_key = public_key
    access_key.vpn_ip = vpn_ip

    await session.commit()
    await session.refresh(access_key)

    return access_key


async def get_vpn_config(
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

    if key_from_db.vpn_ip is None:
        return "vpn_not_provisioned"

    return {
        "schema_version": 1,
        "server": {
            "name": settings.vpn_server_name,
            "host": settings.vpn_server_host,
            "port": settings.vpn_server_port,
            "public_key": settings.vpn_server_public_key,
        },
        "protocol": {
            "type": "amneziawg",
            "config": {
                "jc": settings.vpn_jc,
                "jmin": settings.vpn_jmin,
                "jmax": settings.vpn_jmax,
                "s1": settings.vpn_s1,
                "s2": settings.vpn_s2,
                "s3": settings.vpn_s3,
                "s4": settings.vpn_s4,
                "h1": settings.vpn_h1,
                "h2": settings.vpn_h2,
                "h3": settings.vpn_h3,
                "h4": settings.vpn_h4,
                "i1": settings.vpn_i1,
            },
        },
        "client": {
            "vpn_ip": key_from_db.vpn_ip,
        },
    }
