from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class LiveRoom(Base):
    """直播间元数据表。

    这里只保存标题、主播、状态和播放地址等控制面数据；视频二进制由媒体
    服务/CDN 分发，不经过 FastAPI 或 MySQL。
    """

    __tablename__ = "live_rooms"
    __table_args__ = (
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
    # push_url 只返回给主播端；观众端只需要 play_url。
    # 两个地址都由服务端生成，客户端不能自行拼接流名称，避免推流和观看房间错配。
    push_url: Mapped[str] = mapped_column(String(1000), nullable=False, default="")
    stream_name: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    category: Mapped[str] = mapped_column(String(100), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
