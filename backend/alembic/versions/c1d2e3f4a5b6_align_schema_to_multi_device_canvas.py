"""align schema to Multi Device Db Schema canvas

Revision ID: c1d2e3f4a5b6
Revises: b8e4a1c02f17
Create Date: 2026-07-31 19:40:00.000000

Canvas fields only:
- access_keys: id, key, status
- devices: id, access_key_id, device_id, platform, vpn_public_key
- vpn_sessions: id, access_key_id, device_id, vpn_ip, started_at
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c1d2e3f4a5b6"
down_revision: Union[str, Sequence[str], None] = "b8e4a1c02f17"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _drop_column_if_exists(table: str, column: str) -> None:
    op.execute(
        sa.text(
            f"""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name = '{table}' AND column_name = '{column}'
                ) THEN
                    EXECUTE 'ALTER TABLE {table} DROP COLUMN {column}';
                END IF;
            END $$;
            """
        )
    )


def _drop_constraint_if_exists(table: str, name: str) -> None:
    op.execute(
        sa.text(
            f"""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM pg_constraint WHERE conname = '{name}'
                ) THEN
                    EXECUTE 'ALTER TABLE {table} DROP CONSTRAINT {name}';
                END IF;
            END $$;
            """
        )
    )


def upgrade() -> None:
    _drop_column_if_exists("devices", "display_name")
    _drop_column_if_exists("devices", "created_at")
    _drop_column_if_exists("devices", "last_seen_at")

    _drop_constraint_if_exists("access_keys", "uq_access_keys_vpn_ip")
    _drop_constraint_if_exists("access_keys", "uq_access_keys_vpn_public_key")
    _drop_column_if_exists("access_keys", "vpn_ip")
    _drop_column_if_exists("access_keys", "vpn_public_key")
    _drop_column_if_exists("access_keys", "device_id")


def downgrade() -> None:
    op.add_column(
        "access_keys",
        sa.Column("device_id", sa.String(), nullable=True),
    )
    op.add_column(
        "access_keys",
        sa.Column("vpn_public_key", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "access_keys",
        sa.Column("vpn_ip", sa.String(length=45), nullable=True),
    )
    op.create_unique_constraint(
        "uq_access_keys_vpn_public_key",
        "access_keys",
        ["vpn_public_key"],
    )
    op.create_unique_constraint(
        "uq_access_keys_vpn_ip",
        "access_keys",
        ["vpn_ip"],
    )
    op.add_column(
        "devices",
        sa.Column("display_name", sa.String(length=128), nullable=True),
    )
    op.add_column(
        "devices",
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.add_column(
        "devices",
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
    )
