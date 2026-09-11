"""虚拟居民与直播公屏历史的持久化模型。"""

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class VirtualResidentProfile(Base):
    """绑定到 User 的虚拟居民资料。

    复用 ``users`` 表意味着虚拟居民可以像其他用户一样拥有动态、关注关系和
    可跳转的主页；``is_virtual`` 与本表共同保证客户端能清楚呈现其虚拟身份。
    """

    __tablename__ = "virtual_resident_profiles"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    role: Mapped[str] = mapped_column(String(48), nullable=False)
    persona: Mapped[str] = mapped_column(Text, nullable=False)
    interests: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    speaking_style: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class LiveChatMessage(Base):
    """直播间公开弹幕历史。

    既为用户重新进入直播间提供历史回填，也为房间导演提供有限上下文。消息
    只保存公开弹幕，不保存私信、鉴权令牌或模型原始推理内容。
    """

    __tablename__ = "live_chat_messages"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    room_id: Mapped[int] = mapped_column(
        ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    body: Mapped[str] = mapped_column(String(200), nullable=False)
    is_virtual: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
