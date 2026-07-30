from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from app.db.session import get_db
from app.services.activation_service import activate_access_key


router = APIRouter()


class ActivationRequest(BaseModel):
    access_key: str
    device_id: str
    vpn_public_key: str


@router.post("/activate")
async def activate(
    request: ActivationRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await activate_access_key(
        session=session,
        access_key=request.access_key,
        device_id=request.device_id,
        vpn_public_key=request.vpn_public_key,
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

    if result == "device_mismatch":
        raise HTTPException(
            status_code=403,
            detail="Access key is activated on another device",
        )

    if result == "session_active":
        raise HTTPException(
            status_code=409,
            detail="VPN session is active; disconnect before re-binding keys",
        )

    if isinstance(result, dict):
        return {
            "message": "Access key activated successfully",
            "status": result["status"],
        }
