from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.access_key import AccessKey
    from app.models.vpn_session import VpnSession


class Device(Base):
    """Bound device — fields match Multi Device Db Schema canvas (no vpn_ip)."""

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

    device_id: Mapped[str] = mapped_column(String(64), nullable=False)

    platform: Mapped[str | None] = mapped_column(String(32), nullable=True)

    vpn_public_key: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
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
