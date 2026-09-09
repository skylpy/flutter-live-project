"""添加动态评论。"""

import sqlalchemy as sa

from alembic import op

revision = "0009_feed_comments"
down_revision = "0008_feed_post_media"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "feed_comments",
        sa.Column("id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"), primary_key=True),
        sa.Column("post_id", sa.BigInteger(), nullable=False),
        sa.Column("author_id", sa.BigInteger(), nullable=False),
        sa.Column("body", sa.String(length=500), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["post_id"], ["feed_posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["author_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_feed_comments_post_id", "feed_comments", ["post_id"])


def downgrade() -> None:
    op.drop_index("ix_feed_comments_post_id", table_name="feed_comments")
    op.drop_table("feed_comments")
