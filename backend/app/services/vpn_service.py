import ipaddress

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.models.access_key import AccessKey
from app.models.device import Device
from app.models.vpn_session import VpnSession


async def allocate_ip(session: AsyncSession) -> str:
    result = await session.execute(select(VpnSession.vpn_ip))
    used_ips = set(result.scalars().all())

    network = ipaddress.ip_network("10.8.0.0/24")

    for ip in network.hosts():
        ip_string = str(ip)

        if ip_string == "10.8.0.1":
            continue

        if ip_string not in used_ips:
            return ip_string

    raise RuntimeError("Свободные VPN-IP закончились")


async def get_vpn_config(
    session: AsyncSession,
    access_key: str,
    device_id: str,
) -> str | dict:
    result = await session.execute(
        select(AccessKey)
        .where(AccessKey.key == access_key)
        .options(selectinload(AccessKey.devices).selectinload(Device.sessions))
    )
    key_from_db = result.scalar_one_or_none()

    if key_from_db is None:
        return "not_found"

    if key_from_db.status == "revoked":
        return "revoked"

    if key_from_db.status != "activated":
        return "not_activated"

    device = next(
        (d for d in key_from_db.devices if d.device_id == device_id),
        None,
    )
    if device is None:
        return "device_mismatch"

    live = device.sessions[0] if device.sessions else None
    if live is None:
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
            "vpn_ip": live.vpn_ip,
        },
    }
