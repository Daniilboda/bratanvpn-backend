from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.device import Device
    from app.models.vpn_session import VpnSession


class AccessKey(Base):
    __tablename__ = "access_keys"

    id: Mapped[int] = mapped_column(primary_key=True)

    key: Mapped[str] = mapped_column(
        String(64),
        unique=True,
        nullable=False,
    )

    status: Mapped[str] = mapped_column(
        String(20),
        default="created",
        nullable=False,
    )

    # Legacy 1-key-1-device fields — kept until API cutover (stage 7).
    device_id: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    vpn_public_key: Mapped[str | None] = mapped_column(
        String(255),
        unique=True,
        nullable=True,
    )

    vpn_ip: Mapped[str | None] = mapped_column(
        String(45),
        unique=True,
        nullable=True,
    )

    devices: Mapped[list[Device]] = relationship(
        "Device",
        back_populates="access_key",
        cascade="all, delete-orphan",
    )
    sessions: Mapped[list[VpnSession]] = relationship(
        "VpnSession",
        back_populates="access_key",
        cascade="all, delete-orphan",
    )
