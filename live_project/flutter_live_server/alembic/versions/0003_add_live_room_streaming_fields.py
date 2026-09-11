"""为直播间增加推流地址和流名称。

Revision ID: 0003_stream_fields
Revises: 0002_create_users
Create Date: 2026-09-05
"""

import sqlalchemy as sa

from alembic import context, op

revision = "0003_stream_fields"
down_revision = "0002_create_users"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """旧房间先填空字符串，新创建房间由 Service 生成真实地址。"""
    # ``--sql`` 使用 MockConnection，不能反射已有列；从 0002 开始生成
    # 的空数据库必然没有这两列，因此离线模式可安全地直接输出 DDL。
    if context.is_offline_mode():
        op.add_column(
            "live_rooms",
            sa.Column("push_url", sa.String(length=1000), nullable=False, server_default=""),
        )
        op.add_column(
            "live_rooms",
            sa.Column("stream_name", sa.String(length=255), nullable=False, server_default=""),
        )
        return
    # MySQL 的 DDL 不参与事务。上一次如果已成功加列、但在写入 alembic
    # 版本号时失败，重复执行迁移不能再次 add column。
    existing_columns = {
        column["name"] for column in sa.inspect(op.get_bind()).get_columns("live_rooms")
    }
    if "push_url" not in existing_columns:
        op.add_column(
            "live_rooms",
            sa.Column(
                "push_url",
                sa.String(length=1000),
                nullable=False,
                server_default="",
            ),
        )
    if "stream_name" not in existing_columns:
        op.add_column(
            "live_rooms",
            sa.Column(
                "stream_name",
                sa.String(length=255),
                nullable=False,
                server_default="",
            ),
        )


def downgrade() -> None:
    """回滚时删除本次新增的控制面字段。"""
    op.drop_column("live_rooms", "stream_name")
    op.drop_column("live_rooms", "push_url")
