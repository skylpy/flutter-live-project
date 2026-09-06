"""增加 Phase 2 动态、消息和互动数据表。

Revision ID: 0005_phase2_social
Revises: 0004_allow_repeated_names
Create Date: 2026-09-06
"""

import sqlalchemy as sa

from alembic import op

revision = "0005_phase2_social"
down_revision = "0004_allow_repeated_names"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """创建动态、关注、私信和直播间互动表。"""
    op.create_table(
        "feed_posts",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("author_id", sa.BigInteger(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("media_kind", sa.String(length=20), nullable=False),
        sa.Column("likes_count", sa.Integer(), nullable=False),
        sa.Column("comments_count", sa.Integer(), nullable=False),
        sa.Column("shares_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["author_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_feed_posts_author_id", "feed_posts", ["author_id"])

    op.create_table(
        "feed_likes",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("post_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["post_id"], ["feed_posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("post_id", "user_id", name="uq_feed_likes_post_user"),
    )

    op.create_table(
        "follows",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("follower_id", sa.BigInteger(), nullable=False),
        sa.Column("followed_id", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["follower_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["followed_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("follower_id", "followed_id", name="uq_follows_pair"),
    )

    op.create_table(
        "direct_messages",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("sender_id", sa.BigInteger(), nullable=False),
        sa.Column("recipient_id", sa.BigInteger(), nullable=False),
        sa.Column("body", sa.String(length=2000), nullable=False),
        sa.Column("is_read", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )

    for table_name, unique_name in (
        ("live_room_follows", "uq_live_room_follows_room_user"),
        ("live_room_likes", "uq_live_room_likes_room_user"),
    ):
        op.create_table(
            table_name,
            sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
            sa.Column("room_id", sa.BigInteger(), nullable=False),
            sa.Column("user_id", sa.BigInteger(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["room_id"], ["live_rooms.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("room_id", "user_id", name=unique_name),
        )


def downgrade() -> None:
    """按依赖关系反向删除 Phase 2 表。"""
    op.drop_table("live_room_likes")
    op.drop_table("live_room_follows")
    op.drop_table("direct_messages")
    op.drop_table("follows")
    op.drop_table("feed_likes")
    op.drop_index("ix_feed_posts_author_id", table_name="feed_posts")
    op.drop_table("feed_posts")
