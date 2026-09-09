"""关联动态与已确认的 OSS 文件。"""

import sqlalchemy as sa

from alembic import op

revision = "0008_feed_post_media"
down_revision = "0007_file_records"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "feed_post_media",
        sa.Column("id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"), primary_key=True),
        sa.Column("post_id", sa.BigInteger(), nullable=False),
        sa.Column("file_id", sa.BigInteger(), nullable=False),
        sa.Column("media_type", sa.String(length=10), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["post_id"], ["feed_posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["file_id"], ["file_records.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("file_id", name="uq_feed_post_media_file"),
        sa.UniqueConstraint("post_id", "sort_order", name="uq_feed_post_media_order"),
    )
    op.create_index("ix_feed_post_media_post_id", "feed_post_media", ["post_id"])


def downgrade() -> None:
    op.drop_index("ix_feed_post_media_post_id", table_name="feed_post_media")
    op.drop_table("feed_post_media")
