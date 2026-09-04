"""创建直播间元数据表。

该迁移只建立控制面数据，不创建视频文件或流媒体二进制字段。

Revision ID: 0001_create_live_rooms
Revises:
Create Date: 2026-09-03
"""

import sqlalchemy as sa

from alembic import op

revision = "0001_create_live_rooms"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    """创建 live_rooms 表和查询直播状态需要的索引。"""
    op.create_table(
        "live_rooms",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("anchor_name", sa.String(length=100), nullable=False),
        sa.Column("anchor_avatar", sa.String(length=500), nullable=False),
        sa.Column("cover_url", sa.String(length=500), nullable=False),
        sa.Column("online_count", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("play_url", sa.String(length=1000), nullable=False),
        sa.Column("category", sa.String(length=100), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("title", "anchor_name", name="uq_live_rooms_title_anchor"),
    )
    op.create_index("ix_live_rooms_status", "live_rooms", ["status"], unique=False)
    op.create_index(
        "ix_live_rooms_status_created_at",
        "live_rooms",
        ["status", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    """回滚本次迁移，删除直播间表及其索引。"""
    op.drop_index("ix_live_rooms_status_created_at", table_name="live_rooms")
    op.drop_index("ix_live_rooms_status", table_name="live_rooms")
    op.drop_table("live_rooms")
