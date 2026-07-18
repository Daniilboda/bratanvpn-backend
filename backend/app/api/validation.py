from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.access_key_service import validate_access_key


router = APIRouter(
    prefix="/validate",
    tags=["Validation"],
)


class ValidationRequest(BaseModel):
    key: str
    device_id: str

@router.post("")
async def validate_key(
    request: ValidationRequest,
    session: AsyncSession = Depends(get_db),
):
    validation_result = await validate_access_key(
        session=session,
        key=request.key,
        device_id=request.device_id,
    )

    return {
        "status": validation_result,
    }