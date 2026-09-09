"""OSS 文件记录及待确认上传意向。"""

import sqlalchemy as sa

from alembic import op

revision = "0007_file_records"
down_revision = "0006_live_room_owner"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "file_records",
        sa.Column("id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"), primary_key=True),
        sa.Column("user_id", sa.BigInteger(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("object_key", sa.String(512), nullable=False),
        sa.Column("original_filename", sa.String(255), nullable=False),
        sa.Column("content_type", sa.String(128), nullable=False),
        sa.Column("file_size", sa.BigInteger(), nullable=False),
        sa.Column("category", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("object_key", name="uq_file_records_object_key"),
    )
    op.create_index("ix_file_records_user_id", "file_records", ["user_id"])
    op.create_index("ix_file_records_status", "file_records", ["status"])


def downgrade():
    op.drop_table("file_records")
