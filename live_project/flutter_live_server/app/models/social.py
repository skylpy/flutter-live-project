from datetime import datetime
from typing import Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class FeedPost(Base):
    """动态正文表。

    动态是控制面数据，正文和计数保存在 MySQL；图片/视频字节位于对象存储，
    并通过 ``FeedPostMedia`` 关联到已确认的文件记录。
    """

    __tablename__ = "feed_posts"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    media_kind: Mapped[str] = mapped_column(String(20), nullable=False, default="none")
    likes_count: Mapped[int] = mapped_column(nullable=False, default=0)
    comments_count: Mapped[int] = mapped_column(nullable=False, default=0)
    shares_count: Mapped[int] = mapped_column(nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class FeedPostMedia(Base):
    """动态与已确认 OSS 文件的关联。

    文件控制面仍归 ``file_records`` 管理；动态只保存文件 ID 和展示顺序，
    每次读取时由服务端按当前用户签发短期访问 URL。
    """

    __tablename__ = "feed_post_media"
    __table_args__ = (UniqueConstraint("post_id", "sort_order", name="uq_feed_post_media_order"),)

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    post_id: Mapped[int] = mapped_column(
        ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    file_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("file_records.id", ondelete="RESTRICT"), nullable=True, unique=True
    )
    # 虚拟居民的项目内媒体库不经过用户上传/OSS 签名，使用受控的相对静态地址。
    # 二者至少有一个存在；用户动态仍只允许使用 file_id。
    source_url: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    media_type: Mapped[str] = mapped_column(String(10), nullable=False)
    sort_order: Mapped[int] = mapped_column(nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class FeedComment(Base):
    """动态公开评论；``parent_id`` 指向同一动态中的被回复评论。"""

    __tablename__ = "feed_comments"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    post_id: Mapped[int] = mapped_column(
        ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    author_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    parent_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("feed_comments.id", ondelete="CASCADE"), nullable=True, index=True
    )
    body: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class FeedLike(Base):
    """用户对动态的幂等点赞记录。"""

    __tablename__ = "feed_likes"
    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_feed_likes_post_user"),)

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    post_id: Mapped[int] = mapped_column(
        ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class Follow(Base):
    """用户关注关系；同一对用户只能存在一条关系。"""

    __tablename__ = "follows"
    __table_args__ = (UniqueConstraint("follower_id", "followed_id", name="uq_follows_pair"),)

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    follower_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    followed_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class DirectMessage(Base):
    """最小私信表。

    消息列表先按会话聚合返回；后续增加分页时只扩展 Repository 查询，不改页面。
    """

    __tablename__ = "direct_messages"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    sender_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    recipient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    body: Mapped[str] = mapped_column(String(2000), nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class DirectMessageMedia(Base):
    """私信内共享的图片或视频文件关联。

    文件本体仍由 ``file_records`` 和 OSS 管理；只有会话双方能通过私信接口
    拿到短期访问 URL。一个文件可在多条私信中引用，因此文件删除时需检查引用。
    """

    __tablename__ = "direct_message_media"
    __table_args__ = (
        UniqueConstraint("message_id", "sort_order", name="uq_direct_message_media_order"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    message_id: Mapped[int] = mapped_column(
        ForeignKey("direct_messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    file_id: Mapped[int] = mapped_column(
        ForeignKey("file_records.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    media_type: Mapped[str] = mapped_column(String(10), nullable=False)
    sort_order: Mapped[int] = mapped_column(nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class LiveRoomFollow(Base):
    """观众对直播间的关注关系。"""

    __tablename__ = "live_room_follows"
    __table_args__ = (
        UniqueConstraint("room_id", "user_id", name="uq_live_room_follows_room_user"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(
        ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class LiveRoomLike(Base):
    """观众对直播间的点赞关系；重复点击由删除记录实现取消点赞。"""

    __tablename__ = "live_room_likes"
    __table_args__ = (UniqueConstraint("room_id", "user_id", name="uq_live_room_likes_room_user"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(
        ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
