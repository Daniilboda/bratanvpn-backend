"""move vpn fields to access_keys

Revision ID: a3f2c8d91e04
Revises: 17a448b79be1
Create Date: 2026-07-19 18:50:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a3f2c8d91e04"
down_revision: Union[str, Sequence[str], None] = "17a448b79be1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
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
    op.drop_table("vpn_clients")


def downgrade() -> None:
    op.create_table(
        "vpn_clients",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("access_key_id", sa.Integer(), nullable=False),
        sa.Column("public_key", sa.String(length=255), nullable=False),
        sa.Column("vpn_ip", sa.String(length=45), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["access_key_id"], ["access_keys.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("access_key_id"),
        sa.UniqueConstraint("public_key"),
        sa.UniqueConstraint("vpn_ip"),
    )
    op.drop_constraint("uq_access_keys_vpn_ip", "access_keys", type_="unique")
    op.drop_constraint("uq_access_keys_vpn_public_key", "access_keys", type_="unique")
    op.drop_column("access_keys", "vpn_ip")
    op.drop_column("access_keys", "vpn_public_key")
