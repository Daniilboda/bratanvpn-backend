from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.vpn_service import get_vpn_config

router = APIRouter(
    prefix="/vpn",
    tags=["VPN"],
)


@router.get("/config")
async def vpn_config(
    access_key: str,
    device_id: str,
    session: AsyncSession = Depends(get_db),
):
    result = await get_vpn_config(
        session=session,
        access_key=access_key,
        device_id=device_id,
    )

    if result == "not_found":
        raise HTTPException(
            status_code=404,
            detail="Access key not found",
        )

    if result == "revoked":
        raise HTTPException(
            status_code=403,
            detail="Access key is revoked",
        )

    if result == "not_activated":
        raise HTTPException(
            status_code=403,
            detail="Access key is not activated",
        )

    if result == "device_mismatch":
        raise HTTPException(
            status_code=403,
            detail="Access key is activated on another device",
        )

    if result == "vpn_not_provisioned":
        raise HTTPException(
            status_code=409,
            detail="VPN is not provisioned for this access key",
        )

    return result
