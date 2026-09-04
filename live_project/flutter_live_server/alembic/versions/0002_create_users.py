"""创建用户表。

password_hash 保存密码哈希，绝不保存用户明文密码。

Revision ID: 0002_create_users
Revises: 0001_create_live_rooms
Create Date: 2026-09-03
"""

import sqlalchemy as sa

from alembic import op

revision = "0002_create_users"
down_revision = "0001_create_live_rooms"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """创建 users 表和用户名索引。"""
    op.create_table(
        "users",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("username", sa.String(length=50), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("username"),
    )
    op.create_index("ix_users_username", "users", ["username"], unique=False)


def downgrade() -> None:
    """回滚本次迁移，删除用户表及索引。"""
    op.drop_index("ix_users_username", table_name="users")
    op.drop_table("users")
