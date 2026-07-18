from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel


from app.db.session import get_db
from app.services.activation_service import activate_access_key


router = APIRouter()



class ActivationRequest(BaseModel):
    access_key: str
    device_id: str

@router.post("/activate")
async def activate(
    request: ActivationRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await activate_access_key(
        session=session,
        access_key=request.access_key,
        device_id=request.device_id,
    )

    if result == "not_found":
        raise HTTPException(
            status_code=404,
            detail="Access key not found",
    )

    if result == "already_activated":
        raise HTTPException(
            status_code=409,
            detail="Access key is already activated on this device",
        )

    if result == "device_mismatch":
        raise HTTPException(
            status_code=403,
            detail="Access key is activated on another device",
        )

    return {
        "message": "Access key activated successfully",
    }