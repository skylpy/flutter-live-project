"""为直播间增加主播归属，保护房间生命周期接口。

Revision ID: 0006_live_room_owner
Revises: 0005_phase2_social
Create Date: 2026-09-07
"""

import sqlalchemy as sa

from alembic import context, op

revision = "0006_live_room_owner"
down_revision = "0005_phase2_social"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """为新房间记录创建者；历史房间保留为空以兼容已有数据。"""
    if context.is_offline_mode():
        op.add_column(
            "live_rooms",
            sa.Column("anchor_user_id", sa.BigInteger(), nullable=True),
        )
        op.create_index(
            "ix_live_rooms_anchor_user_id",
            "live_rooms",
            ["anchor_user_id"],
        )
        op.create_foreign_key(
            "fk_live_rooms_anchor_user_id_users",
            "live_rooms",
            "users",
            ["anchor_user_id"],
            ["id"],
            ondelete="SET NULL",
        )
        return
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("live_rooms")}
    if "anchor_user_id" not in columns:
        op.add_column(
            "live_rooms",
            sa.Column("anchor_user_id", sa.BigInteger(), nullable=True),
        )
        op.create_index(
            "ix_live_rooms_anchor_user_id",
            "live_rooms",
            ["anchor_user_id"],
        )
        op.create_foreign_key(
            "fk_live_rooms_anchor_user_id_users",
            "live_rooms",
            "users",
            ["anchor_user_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    """删除主播归属字段。"""
    op.drop_constraint(
        "fk_live_rooms_anchor_user_id_users",
        "live_rooms",
        type_="foreignkey",
    )
    op.drop_index("ix_live_rooms_anchor_user_id", table_name="live_rooms")
    op.drop_column("live_rooms", "anchor_user_id")
