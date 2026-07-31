from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.access_key import AccessKey
    from app.models.device import Device


class VpnSession(Base):
    """Active (or historical) VPN slot for a bound device."""

    __tablename__ = "vpn_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)

    access_key_id: Mapped[int] = mapped_column(
        ForeignKey("access_keys.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Snapshot of assigned IP while this session row is the active one.
    vpn_ip: Mapped[str | None] = mapped_column(String(45), nullable=True)

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    ended_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )

    access_key: Mapped[AccessKey] = relationship(
        "AccessKey",
        back_populates="sessions",
    )
    device: Mapped[Device] = relationship(
        "Device",
        back_populates="sessions",
    )
