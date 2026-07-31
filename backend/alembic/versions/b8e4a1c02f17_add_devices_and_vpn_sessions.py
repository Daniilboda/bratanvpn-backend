"""add devices and vpn_sessions tables

Revision ID: b8e4a1c02f17
Revises: a3f2c8d91e04
Create Date: 2026-07-31 18:55:00.000000

Creates devices + vpn_sessions per Multi Device Db Schema canvas.
Revision c1d2e3f4a5b6 drops access_keys legacy columns / device extras
if an older draft of this migration was already applied.
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
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("vpn_public_key", sa.String(length=255), nullable=False),
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
    )
    op.create_index("ix_devices_access_key_id", "devices", ["access_key_id"])

    op.create_table(
        "vpn_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("access_key_id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.Integer(), nullable=False),
        sa.Column("vpn_ip", sa.String(length=45), nullable=False),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
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
        sa.UniqueConstraint("device_id", name="uq_vpn_sessions_device_id"),
        sa.UniqueConstraint("vpn_ip", name="uq_vpn_sessions_vpn_ip"),
    )
    op.create_index(
        "ix_vpn_sessions_access_key_id",
        "vpn_sessions",
        ["access_key_id"],
    )

    op.execute(
        sa.text(
            """
            INSERT INTO devices (
                access_key_id,
                device_id,
                platform,
                vpn_public_key
            )
            SELECT
                ak.id,
                ak.device_id,
                NULL,
                ak.vpn_public_key
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
                started_at
            )
            SELECT
                d.access_key_id,
                d.id,
                ak.vpn_ip,
                now()
            FROM devices AS d
            JOIN access_keys AS ak ON ak.id = d.access_key_id
            WHERE ak.vpn_ip IS NOT NULL
            """
        )
    )


def downgrade() -> None:
    op.drop_index("ix_vpn_sessions_access_key_id", table_name="vpn_sessions")
    op.drop_table("vpn_sessions")
    op.drop_index("ix_devices_access_key_id", table_name="devices")
    op.drop_table("devices")
