"""添加虚拟居民媒体库和动态评论回复关系。"""

import sqlalchemy as sa

from alembic import op

revision = "0013_ai_social"
down_revision = "0012_ai_live_chat"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 用户上传媒体仍通过 file_id 绑定；虚拟居民只能引用项目内受控静态媒体。
    op.add_column("feed_post_media", sa.Column("source_url", sa.String(length=1000), nullable=True))
    op.alter_column(
        "feed_post_media",
        "file_id",
        existing_type=sa.BigInteger(),
        nullable=True,
    )
    op.add_column("feed_comments", sa.Column("parent_id", sa.BigInteger(), nullable=True))
    op.create_foreign_key(
        "fk_feed_comments_parent_id",
        "feed_comments",
        "feed_comments",
        ["parent_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index("ix_feed_comments_parent_id", "feed_comments", ["parent_id"])


def downgrade() -> None:
    op.drop_index("ix_feed_comments_parent_id", table_name="feed_comments")
    op.drop_constraint("fk_feed_comments_parent_id", "feed_comments", type_="foreignkey")
    op.drop_column("feed_comments", "parent_id")
    op.alter_column(
        "feed_post_media",
        "file_id",
        existing_type=sa.BigInteger(),
        nullable=False,
    )
    op.drop_column("feed_post_media", "source_url")
