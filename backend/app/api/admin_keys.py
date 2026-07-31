from fastapi import APIRouter, Depends, HTTPException
from app.core.security import verify_admin_key
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from app.db.session import get_db
from app.services.access_key_service import (
    create_access_key,
    get_access_key,
    get_access_keys,
    restore_access_key,
    revoke_access_key,
)

router = APIRouter(
    prefix="/admin/keys",
    tags=["Admin keys"],
    dependencies=[
        Depends(verify_admin_key),
    ],
)

@router.post("")
async def create_key(
    session: AsyncSession = Depends(get_db),
):
    new_key = await create_access_key(session)

    return {
        "key": new_key.key,
        "status": new_key.status,
    }


class RevokeKeyRequest(BaseModel):
    key: str

@router.patch("/revoke")
async def revoke_key(
    request: RevokeKeyRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await revoke_access_key(
        session=session,
        key=request.key,
    )

    if result == "vpn_agent_failed":
        raise HTTPException(
            status_code=502,
            detail="Failed to remove VPN peer on server",
        )

    return {
        "status": result,
    }


class RestoreKeyRequest(BaseModel):
    key: str


@router.patch("/restore")
async def restore_key(
    request: RestoreKeyRequest,
    session: AsyncSession = Depends(get_db),
):
    result = await restore_access_key(
        session=session,
        key=request.key,
    )

    return {
        "status": result,
    }


@router.get("")
async def get_keys(
    status: str | None = None,
    session: AsyncSession = Depends(get_db),
):
    keys = await get_access_keys(
        session=session,
        status=status,
    )

    return [
        {
            "id": key.id,
            "key": key.key,
            "status": key.status,
        }
        for key in keys
    ]


@router.get("/{key}")
async def get_key(
    key: str,
    session: AsyncSession = Depends(get_db),
):
    key_from_db = await get_access_key(
        session=session,
        key=key,
    )

    if key_from_db is None:
        return {
            "status": "not_found",
        }

    return {
        "id": key_from_db.id,
        "key": key_from_db.key,
        "status": key_from_db.status,
    }