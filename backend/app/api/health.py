from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.health_service import build_health_report, maybe_notify_health

router = APIRouter(tags=["Health"])


@router.get("/health")
async def health(session: AsyncSession = Depends(get_db)) -> dict[str, object]:
    report = await build_health_report(session)
    await maybe_notify_health(report)
    return report
