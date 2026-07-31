from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.access_key import AccessKey
    from app.models.device import Device


class VpnSession(Base):
    """Live VPN slot only. Disconnect/revoke → DELETE this row (no soft-close)."""

    __tablename__ = "vpn_sessions"
    __table_args__ = (
        UniqueConstraint("device_id", name="uq_vpn_sessions_device_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    access_key_id: Mapped[int] = mapped_column(
        ForeignKey("access_keys.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"),
        nullable=False,
    )

    vpn_ip: Mapped[str] = mapped_column(
        String(45),
        unique=True,
        nullable=False,
    )

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    access_key: Mapped[AccessKey] = relationship(
        "AccessKey",
        back_populates="sessions",
    )
    device: Mapped[Device] = relationship(
        "Device",
        back_populates="sessions",
    )
