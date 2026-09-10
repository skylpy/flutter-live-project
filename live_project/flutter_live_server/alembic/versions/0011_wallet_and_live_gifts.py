"""添加测试钱包、不可变流水和直播礼物。"""

from datetime import datetime

import sqlalchemy as sa

from alembic import op

revision = "0011_wallet_and_live_gifts"
down_revision = "0010_direct_message_media"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "wallets",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("available_balance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("income_balance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", name="uq_wallets_user_id"),
    )
    op.create_index("ix_wallets_user_id", "wallets", ["user_id"])

    op.create_table(
        "wallet_ledgers",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("wallet_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("balance_type", sa.String(length=20), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("balance_after", sa.Integer(), nullable=False),
        sa.Column("business_type", sa.String(length=40), nullable=False),
        sa.Column("reference_type", sa.String(length=40), nullable=False, server_default=""),
        sa.Column("reference_id", sa.BigInteger(), nullable=True),
        sa.Column("idempotency_key", sa.String(length=160), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["wallet_id"], ["wallets.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idempotency_key", name="uq_wallet_ledgers_idempotency_key"),
    )
    op.create_index("ix_wallet_ledgers_wallet_id", "wallet_ledgers", ["wallet_id"])
    op.create_index("ix_wallet_ledgers_user_id", "wallet_ledgers", ["user_id"])
    op.create_index("ix_wallet_ledgers_reference_id", "wallet_ledgers", ["reference_id"])
    op.create_index("ix_wallet_ledgers_created_at", "wallet_ledgers", ["created_at"])

    op.create_table(
        "gift_catalog",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column("icon", sa.String(length=32), nullable=False),
        sa.Column("animation_key", sa.String(length=80), nullable=False),
        sa.Column("price", sa.Integer(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_gift_catalog_is_active", "gift_catalog", ["is_active"])

    now = datetime.utcnow()
    gifts = sa.table(
        "gift_catalog",
        sa.column("id", sa.BigInteger()),
        sa.column("name", sa.String()),
        sa.column("icon", sa.String()),
        sa.column("animation_key", sa.String()),
        sa.column("price", sa.Integer()),
        sa.column("sort_order", sa.Integer()),
        sa.column("is_active", sa.Boolean()),
        sa.column("created_at", sa.DateTime()),
        sa.column("updated_at", sa.DateTime()),
    )
    op.bulk_insert(
        gifts,
        [
            {"id": 1, "name": "小心心", "icon": "💗", "animation_key": "heart", "price": 10, "sort_order": 10, "is_active": True, "created_at": now, "updated_at": now},
            {"id": 2, "name": "玫瑰", "icon": "🌹", "animation_key": "rose", "price": 66, "sort_order": 20, "is_active": True, "created_at": now, "updated_at": now},
            {"id": 3, "name": "星光", "icon": "✨", "animation_key": "starlight", "price": 199, "sort_order": 30, "is_active": True, "created_at": now, "updated_at": now},
            {"id": 4, "name": "城堡", "icon": "🏰", "animation_key": "castle", "price": 999, "sort_order": 40, "is_active": True, "created_at": now, "updated_at": now},
        ],
    )

    op.create_table(
        "gift_transactions",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("room_id", sa.BigInteger(), nullable=False),
        sa.Column("sender_id", sa.BigInteger(), nullable=False),
        sa.Column("anchor_id", sa.BigInteger(), nullable=False),
        sa.Column("gift_id", sa.BigInteger(), nullable=False),
        sa.Column("gift_name", sa.String(length=60), nullable=False),
        sa.Column("gift_icon", sa.String(length=32), nullable=False),
        sa.Column("animation_key", sa.String(length=80), nullable=False),
        sa.Column("unit_price", sa.Integer(), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("total_amount", sa.Integer(), nullable=False),
        sa.Column("idempotency_key", sa.String(length=120), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["room_id"], ["live_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["anchor_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["gift_id"], ["gift_catalog.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idempotency_key", name="uq_gift_transactions_idempotency_key"),
    )
    op.create_index("ix_gift_transactions_room_id", "gift_transactions", ["room_id"])
    op.create_index("ix_gift_transactions_sender_id", "gift_transactions", ["sender_id"])
    op.create_index("ix_gift_transactions_anchor_id", "gift_transactions", ["anchor_id"])
    op.create_index("ix_gift_transactions_created_at", "gift_transactions", ["created_at"])

    op.create_table(
        "live_room_gift_stats",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("room_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("total_amount", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("gift_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["room_id"], ["live_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("room_id", "user_id", name="uq_live_room_gift_stats_room_user"),
    )
    op.create_index("ix_live_room_gift_stats_room_id", "live_room_gift_stats", ["room_id"])
    op.create_index("ix_live_room_gift_stats_user_id", "live_room_gift_stats", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_live_room_gift_stats_user_id", table_name="live_room_gift_stats")
    op.drop_index("ix_live_room_gift_stats_room_id", table_name="live_room_gift_stats")
    op.drop_table("live_room_gift_stats")
    op.drop_index("ix_gift_transactions_created_at", table_name="gift_transactions")
    op.drop_index("ix_gift_transactions_anchor_id", table_name="gift_transactions")
    op.drop_index("ix_gift_transactions_sender_id", table_name="gift_transactions")
    op.drop_index("ix_gift_transactions_room_id", table_name="gift_transactions")
    op.drop_table("gift_transactions")
    op.drop_index("ix_gift_catalog_is_active", table_name="gift_catalog")
    op.drop_table("gift_catalog")
    op.drop_index("ix_wallet_ledgers_created_at", table_name="wallet_ledgers")
    op.drop_index("ix_wallet_ledgers_reference_id", table_name="wallet_ledgers")
    op.drop_index("ix_wallet_ledgers_user_id", table_name="wallet_ledgers")
    op.drop_index("ix_wallet_ledgers_wallet_id", table_name="wallet_ledgers")
    op.drop_table("wallet_ledgers")
    op.drop_index("ix_wallets_user_id", table_name="wallets")
    op.drop_table("wallets")
