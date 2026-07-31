from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.access_key import AccessKey
    from app.models.vpn_session import VpnSession


class Device(Base):
    """Bound client device for an access key (bind ≠ connect)."""

    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint(
            "access_key_id",
            "device_id",
            name="uq_devices_access_key_device_id",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    access_key_id: Mapped[int] = mapped_column(
        ForeignKey("access_keys.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Client-generated id from vault (not the DB primary key).
    device_id: Mapped[str] = mapped_column(String(64), nullable=False)

    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)

    platform: Mapped[str | None] = mapped_column(String(32), nullable=True)

    vpn_public_key: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
    )

    # Only set while an active VPN session exists for this device.
    vpn_ip: Mapped[str | None] = mapped_column(
        String(45),
        unique=True,
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    access_key: Mapped[AccessKey] = relationship(
        "AccessKey",
        back_populates="devices",
    )
    sessions: Mapped[list[VpnSession]] = relationship(
        "VpnSession",
        back_populates="device",
        cascade="all, delete-orphan",
    )
