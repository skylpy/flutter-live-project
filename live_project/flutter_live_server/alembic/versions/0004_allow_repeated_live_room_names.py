"""允许历史直播场次复用标题和主播名称。

Revision ID: 0004_allow_repeated_room_names
Revises: 0003_stream_fields
Create Date: 2026-09-05
"""

import sqlalchemy as sa

from alembic import op

revision = "0004_allow_repeated_names"
down_revision = "0003_stream_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """删除旧的永久唯一索引。

    同一个主播可以在不同日期多次使用相同标题。真正需要唯一的是服务端
    生成的 stream_name，它保证每次 RTMP 推流都不会串到历史房间。
    MySQL 通常把 ORM 的 UniqueConstraint 落成同名唯一索引，因此优先按
    索引删除；如果某个数据库方言只暴露为约束，则退回 drop_constraint。
    """
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    index_names = {index["name"] for index in inspector.get_indexes("live_rooms")}
    constraint_names = {
        constraint["name"]
        for constraint in inspector.get_unique_constraints("live_rooms")
        if constraint.get("name")
    }

    if "uq_live_rooms_title_anchor" in index_names:
        op.drop_index("uq_live_rooms_title_anchor", table_name="live_rooms")
    elif "uq_live_rooms_title_anchor" in constraint_names:
        op.drop_constraint(
            "uq_live_rooms_title_anchor",
            "live_rooms",
            type_="unique",
        )


def downgrade() -> None:
    """回滚时恢复旧约束；已有重复历史数据时由数据库报告冲突。"""
    op.create_unique_constraint(
        "uq_live_rooms_title_anchor",
        "live_rooms",
        ["title", "anchor_name"],
    )
