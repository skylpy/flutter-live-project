"""添加虚拟居民身份和直播间公开弹幕历史。"""

import sqlalchemy as sa

from alembic import op

# Keep revision identifiers within the existing MySQL alembic_version
# VARCHAR(32) column.  The descriptive filename retains the full context.
revision = "0012_ai_live_chat"
down_revision = "0011_wallet_and_live_gifts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("is_virtual", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.alter_column("users", "is_virtual", server_default=None)

    op.create_table(
        "virtual_resident_profiles",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("role", sa.String(length=48), nullable=False),
        sa.Column("persona", sa.Text(), nullable=False),
        sa.Column("interests", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("speaking_style", sa.String(length=500), nullable=False, server_default=""),
        sa.Column("is_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", name="uq_virtual_resident_profiles_user_id"),
    )
    op.create_index(
        "ix_virtual_resident_profiles_user_id", "virtual_resident_profiles", ["user_id"]
    )

    op.create_table(
        "live_chat_messages",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("room_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("body", sa.String(length=200), nullable=False),
        sa.Column("is_virtual", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["room_id"], ["live_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_live_chat_messages_room_id", "live_chat_messages", ["room_id"])
    op.create_index("ix_live_chat_messages_user_id", "live_chat_messages", ["user_id"])
    op.create_index("ix_live_chat_messages_created_at", "live_chat_messages", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_live_chat_messages_created_at", table_name="live_chat_messages")
    op.drop_index("ix_live_chat_messages_user_id", table_name="live_chat_messages")
    op.drop_index("ix_live_chat_messages_room_id", table_name="live_chat_messages")
    op.drop_table("live_chat_messages")
    op.drop_index("ix_virtual_resident_profiles_user_id", table_name="virtual_resident_profiles")
    op.drop_table("virtual_resident_profiles")
    op.drop_column("users", "is_virtual")
