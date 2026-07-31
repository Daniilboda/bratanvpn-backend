"""add devices and vpn_sessions tables

Revision ID: b8e4a1c02f17
Revises: a3f2c8d91e04
Create Date: 2026-07-31 18:55:00.000000

Stage 1: new tables only. Legacy columns on access_keys stay in place.
Existing activated keys are copied into one Device (+ VpnSession if vpn_ip).
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b8e4a1c02f17"
down_revision: Union[str, Sequence[str], None] = "a3f2c8d91e04"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "devices",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("access_key_id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("display_name", sa.String(length=128), nullable=True),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("vpn_public_key", sa.String(length=255), nullable=False),
        sa.Column("vpn_ip", sa.String(length=45), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["access_key_id"],
            ["access_keys.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "access_key_id",
            "device_id",
            name="uq_devices_access_key_device_id",
        ),
        sa.UniqueConstraint("vpn_public_key", name="uq_devices_vpn_public_key"),
        sa.UniqueConstraint("vpn_ip", name="uq_devices_vpn_ip"),
    )
    op.create_index("ix_devices_access_key_id", "devices", ["access_key_id"])

    op.create_table(
        "vpn_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("access_key_id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.Integer(), nullable=False),
        sa.Column("vpn_ip", sa.String(length=45), nullable=True),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "active",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["access_key_id"],
            ["access_keys.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["device_id"],
            ["devices.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_vpn_sessions_access_key_id",
        "vpn_sessions",
        ["access_key_id"],
    )
    op.create_index("ix_vpn_sessions_device_id", "vpn_sessions", ["device_id"])
    # At most one active session row per device.
    op.create_index(
        "uq_vpn_sessions_device_active",
        "vpn_sessions",
        ["device_id"],
        unique=True,
        postgresql_where=sa.text("active IS TRUE"),
    )

    # Copy legacy 1-device bindings into the new tables (API still uses access_keys).
    op.execute(
        sa.text(
            """
            INSERT INTO devices (
                access_key_id,
                device_id,
                display_name,
                platform,
                vpn_public_key,
                vpn_ip,
                created_at,
                last_seen_at
            )
            SELECT
                ak.id,
                ak.device_id,
                NULL,
                NULL,
                ak.vpn_public_key,
                ak.vpn_ip,
                now(),
                now()
            FROM access_keys AS ak
            WHERE ak.device_id IS NOT NULL
              AND ak.vpn_public_key IS NOT NULL
            """
        )
    )
    op.execute(
        sa.text(
            """
            INSERT INTO vpn_sessions (
                access_key_id,
                device_id,
                vpn_ip,
                started_at,
                ended_at,
                active
            )
            SELECT
                d.access_key_id,
                d.id,
                d.vpn_ip,
                now(),
                NULL,
                true
            FROM devices AS d
            WHERE d.vpn_ip IS NOT NULL
            """
        )
    )


def downgrade() -> None:
    op.drop_index(
        "uq_vpn_sessions_device_active",
        table_name="vpn_sessions",
        postgresql_where=sa.text("active IS TRUE"),
    )
    op.drop_index("ix_vpn_sessions_device_id", table_name="vpn_sessions")
    op.drop_index("ix_vpn_sessions_access_key_id", table_name="vpn_sessions")
    op.drop_table("vpn_sessions")
    op.drop_index("ix_devices_access_key_id", table_name="devices")
    op.drop_table("devices")
