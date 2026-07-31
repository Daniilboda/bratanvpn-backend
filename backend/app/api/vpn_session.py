from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.vpn_session_service import connect_vpn_session, disconnect_vpn_session

router = APIRouter(
    prefix="/vpn",
    tags=["VPN"],
)


class VpnSessionRequest(BaseModel):
    access_key: str
    device_id: str


def _raise_for_session_result(result: str | dict) -> dict:
    if result == "not_found":
        raise HTTPException(status_code=404, detail="Access key not found")
    if result == "revoked":
        raise HTTPException(status_code=403, detail="Access key is revoked")
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
    if result == "missing_public_key":
        raise HTTPException(
            status_code=409,
            detail="Device has no VPN public key; activate again",
        )
    if result == "vpn_agent_failed":
        raise HTTPException(
            status_code=502,
            detail="Failed to provision VPN on server",
        )
    if result == "session_limit":
        raise HTTPException(
            status_code=409,
            detail="Active session limit reached (2)",
        )
    if isinstance(result, dict):
        return result
    raise HTTPException(status_code=500, detail="Unexpected VPN session error")


@router.post("/connect")
async def vpn_connect(
    request: VpnSessionRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await connect_vpn_session(
        session=session,
        access_key=request.access_key,
        device_id=request.device_id,
    )
    body = _raise_for_session_result(result)
    return {
        "message": "VPN session started",
        "vpn_ip": body["vpn_ip"],
    }


@router.post("/disconnect")
async def vpn_disconnect(
    request: VpnSessionRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await disconnect_vpn_session(
        session=session,
        access_key=request.access_key,
        device_id=request.device_id,
    )
    _raise_for_session_result(result)
    return {"message": "VPN session stopped"}
