from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class FeedPost(Base):
    """动态正文表。

    动态是控制面数据，正文和计数保存在 MySQL；图片/视频文件仍应放在对象
    存储中，后续只需在这里增加 media_url，不需要改变页面的 Repository 链路。
    """

    __tablename__ = "feed_posts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    media_kind: Mapped[str] = mapped_column(String(20), nullable=False, default="none")
    likes_count: Mapped[int] = mapped_column(nullable=False, default=0)
    comments_count: Mapped[int] = mapped_column(nullable=False, default=0)
    shares_count: Mapped[int] = mapped_column(nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class FeedLike(Base):
    """用户对动态的幂等点赞记录。"""

    __tablename__ = "feed_likes"
    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_feed_likes_post_user"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    post_id: Mapped[int] = mapped_column(ForeignKey("feed_posts.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class Follow(Base):
    """用户关注关系；同一对用户只能存在一条关系。"""

    __tablename__ = "follows"
    __table_args__ = (UniqueConstraint("follower_id", "followed_id", name="uq_follows_pair"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    follower_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    followed_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class DirectMessage(Base):
    """最小私信表。

    消息列表先按会话聚合返回；后续增加分页时只扩展 Repository 查询，不改页面。
    """

    __tablename__ = "direct_messages"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    recipient_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    body: Mapped[str] = mapped_column(String(2000), nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class LiveRoomFollow(Base):
    """观众对直播间的关注关系。"""

    __tablename__ = "live_room_follows"
    __table_args__ = (UniqueConstraint("room_id", "user_id", name="uq_live_room_follows_room_user"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class LiveRoomLike(Base):
    """观众对直播间的点赞关系；重复点击由删除记录实现取消点赞。"""

    __tablename__ = "live_room_likes"
    __table_args__ = (UniqueConstraint("room_id", "user_id", name="uq_live_room_likes_room_user"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
