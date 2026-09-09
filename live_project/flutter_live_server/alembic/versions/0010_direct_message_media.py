"""添加私信媒体附件。"""

import sqlalchemy as sa

from alembic import op

revision = "0010_direct_message_media"
down_revision = "0009_feed_comments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "direct_message_media",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("message_id", sa.BigInteger(), nullable=False),
        sa.Column("file_id", sa.BigInteger(), nullable=False),
        sa.Column("media_type", sa.String(length=10), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["message_id"], ["direct_messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["file_id"], ["file_records.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("message_id", "sort_order", name="uq_direct_message_media_order"),
    )
    op.create_index("ix_direct_message_media_message_id", "direct_message_media", ["message_id"])
    op.create_index("ix_direct_message_media_file_id", "direct_message_media", ["file_id"])


def downgrade() -> None:
    op.drop_index("ix_direct_message_media_file_id", table_name="direct_message_media")
    op.drop_index("ix_direct_message_media_message_id", table_name="direct_message_media")
    op.drop_table("direct_message_media")
