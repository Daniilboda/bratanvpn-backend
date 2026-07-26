"""Health-check: API, DB, disk, VPN agent, outbound internet from VPS."""

from __future__ import annotations

import logging
import shutil
import time

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.services.telegram_notifier import (
    TelegramNotifyError,
    send_telegram_message,
    telegram_configured,
)
from app.services.vpn_agent_client import (
    VpnAgentError,
    agent_status_async,
    check_vps_internet_async,
)

logger = logging.getLogger(__name__)

_last_alert_signature: str | None = None
_last_alert_at: float = 0.0
_was_degraded: bool = False


async def check_database(session: AsyncSession) -> str:
    try:
        await session.execute(text("SELECT 1"))
        return "ok"
    except Exception:
        return "error"


def check_disk_free_mb() -> int:
    usage = shutil.disk_usage(".")
    return usage.free // (1024 * 1024)


def check_disk_status(disk_free_mb: int) -> str:
    if disk_free_mb < settings.health_disk_min_mb:
        return "error"
    return "ok"


async def check_vpn() -> str:
    try:
        await agent_status_async()
        return "ok"
    except VpnAgentError:
        return "error"
    except Exception:
        return "error"


async def check_internet() -> str:
    try:
        await check_vps_internet_async()
        return "ok"
    except VpnAgentError:
        return "error"
    except Exception:
        return "error"


def _problem_signature(report: dict[str, object]) -> str:
    return "|".join(
        [
            f"database={report['database']}",
            f"vpn={report['vpn']}",
            f"internet={report['internet']}",
            f"disk={report['disk']}",
        ]
    )


def _format_alert(report: dict[str, object]) -> str:
    return (
        "BratanVPN: проблемы с работой системы\n"
        f"status: {report['status']}\n"
        f"database: {report['database']}\n"
        f"vpn: {report['vpn']}\n"
        f"internet: {report['internet']}\n"
        f"disk: {report['disk']} ({report['disk_free_mb']} MB free)"
    )


async def maybe_notify_health(report: dict[str, object]) -> None:
    """Send Telegram alert on degraded health (cooldown + dedupe)."""
    global _last_alert_signature, _last_alert_at, _was_degraded

    if not telegram_configured():
        return

    status = report.get("status")
    now = time.monotonic()

    if status == "ok":
        if _was_degraded:
            try:
                await send_telegram_message(
                    "BratanVPN: система снова в норме (status=ok)"
                )
            except TelegramNotifyError:
                logger.exception("Failed to send Telegram recovery message")
            _was_degraded = False
            _last_alert_signature = None
        return

    signature = _problem_signature(report)
    cooldown = settings.telegram_alert_cooldown_seconds
    if (
        signature == _last_alert_signature
        and (now - _last_alert_at) < cooldown
    ):
        return

    try:
        await send_telegram_message(_format_alert(report))
        _last_alert_signature = signature
        _last_alert_at = now
        _was_degraded = True
    except TelegramNotifyError:
        logger.exception("Failed to send Telegram health alert")


async def build_health_report(session: AsyncSession) -> dict[str, object]:
    database = await check_database(session)
    vpn = await check_vpn()
    internet = await check_internet()
    disk_free_mb = check_disk_free_mb()
    disk = check_disk_status(disk_free_mb)

    checks = (database, vpn, internet, disk)
    status = "ok" if all(item == "ok" for item in checks) else "degraded"

    return {
        "status": status,
        "api": "ok",
        "database": database,
        "vpn": vpn,
        "internet": internet,
        "disk": disk,
        "disk_free_mb": disk_free_mb,
    }
