from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class LiveRoom(Base):
    __tablename__ = "live_rooms"
    __table_args__ = (
        UniqueConstraint("title", "anchor_name", name="uq_live_rooms_title_anchor"),
        Index("ix_live_rooms_status_created_at", "status", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    anchor_name: Mapped[str] = mapped_column(String(100), nullable=False)
    anchor_avatar: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    cover_url: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    online_count: Mapped[int] = mapped_column(default=0, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="preparing", index=True)
    play_url: Mapped[str] = mapped_column(String(1000), nullable=False, default="")
    category: Mapped[str] = mapped_column(String(100), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
