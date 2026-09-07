from __future__ import annotations

from datetime import datetime

from sqlalchemy import desc, func, or_, select, update
from sqlalchemy.orm import Session

from app.models.live_room import LiveRoom
from app.models.social import (
    DirectMessage,
    FeedLike,
    FeedPost,
    Follow,
    LiveRoomFollow,
    LiveRoomLike,
)
from app.models.user import User
from app.schemas.social import format_time_label


class SocialRepository:
    """Phase 2 的统一数据访问层。

    路由和 Service 不直接拼 SQL。这样 Flutter Repository 后续改成缓存或分页时，
    服务端数据库查询仍然集中在此处，互动的唯一性也由数据库约束兜底。
    """

    def __init__(self, db: Session) -> None:
        self.db = db

    def list_posts(self, tab: str, user_id: int) -> list[tuple[FeedPost, User, bool]]:
        query = (
            select(FeedPost, User)
            .join(User, User.id == FeedPost.author_id)
            .order_by(desc(FeedPost.created_at))
        )
        if tab == "关注":
            query = query.join(Follow, Follow.followed_id == FeedPost.author_id).where(
                Follow.follower_id == user_id
            )
        rows = self.db.execute(query).all()
        liked_ids = {
            row.post_id
            for row in self.db.scalars(
                select(FeedLike).where(FeedLike.user_id == user_id)
            )
        }
        return [(post, author, post.id in liked_ids) for post, author in rows]

    def toggle_feed_like(self, post_id: int, user_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(FeedLike).where(
                FeedLike.post_id == post_id,
                FeedLike.user_id == user_id,
            )
        )
        post = self.db.get(FeedPost, post_id)
        if post is None:
            return False, 0
        if existing is None:
            self.db.add(FeedLike(post_id=post_id, user_id=user_id, created_at=datetime.utcnow()))
            post.likes_count += 1
            active = True
        else:
            self.db.delete(existing)
            post.likes_count = max(0, post.likes_count - 1)
            active = False
        self.db.commit()
        return active, post.likes_count

    def get_profile(self, user: User) -> dict[str, int | str]:
        following = self.db.scalar(
            select(func.count()).select_from(Follow).where(Follow.follower_id == user.id)
        ) or 0
        followers = self.db.scalar(
            select(func.count()).select_from(Follow).where(Follow.followed_id == user.id)
        ) or 0
        liked = self.db.scalar(
            select(func.coalesce(func.sum(FeedPost.likes_count), 0))
            .select_from(FeedPost)
            .where(FeedPost.author_id == user.id)
        ) or 0
        return {
            "id": user.id,
            "username": user.username,
            "display_name": user.display_name,
            "following_count": int(following),
            "follower_count": int(followers),
            "liked_count": int(liked),
        }

    def update_profile(self, user: User, display_name: str) -> User:
        user.display_name = display_name.strip()
        user.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(user)
        return user

    def list_conversations(self, user_id: int) -> list[dict[str, int | str]]:
        messages = self.db.scalars(
            select(DirectMessage)
            .where(or_(DirectMessage.sender_id == user_id, DirectMessage.recipient_id == user_id))
            .order_by(desc(DirectMessage.created_at))
        ).all()
        latest: dict[int, DirectMessage] = {}
        unread: dict[int, int] = {}
        for message in messages:
            other_id = message.recipient_id if message.sender_id == user_id else message.sender_id
            latest.setdefault(other_id, message)
            if message.recipient_id == user_id and not message.is_read:
                unread[other_id] = unread.get(other_id, 0) + 1
        if not latest:
            return []
        users = {
            user.id: user
            for user in self.db.scalars(select(User).where(User.id.in_(latest)))
        }
        return [
            {
                "user_id": other_id,
                "user_name": users[other_id].display_name if other_id in users else "用户",
                "preview": message.body,
                "time_label": "刚刚",
                "unread": unread.get(other_id, 0),
            }
            for other_id, message in latest.items()
        ]

    def mark_conversation_read(self, user_id: int, other_user_id: int) -> None:
        """把对方发给当前用户的消息真正标记为已读。"""
        self.db.execute(
            update(DirectMessage)
            .where(
                DirectMessage.sender_id == other_user_id,
                DirectMessage.recipient_id == user_id,
                DirectMessage.is_read.is_(False),
            )
            .values(is_read=True)
        )
        self.db.commit()

    def list_notifications(self, user_id: int) -> list[dict[str, str | bool]]:
        """从真实互动数据聚合通知，避免为 MVP 引入重复的通知写入链路。"""
        messages = self.db.execute(
            select(DirectMessage, User)
            .join(User, User.id == DirectMessage.sender_id)
            .where(DirectMessage.recipient_id == user_id)
            .order_by(desc(DirectMessage.created_at))
            .limit(30)
        ).all()
        follows = self.db.execute(
            select(Follow, User)
            .join(User, User.id == Follow.follower_id)
            .where(Follow.followed_id == user_id)
            .order_by(desc(Follow.created_at))
            .limit(30)
        ).all()
        items: list[tuple[datetime, dict[str, str | bool]]] = []
        items.extend(
            (
                message.created_at,
                {
                    "id": f"message:{message.id}",
                    "type": "互动消息",
                    "title": sender.display_name,
                    "body": message.body,
                    "time_label": format_time_label(message.created_at),
                    "unread": not message.is_read,
                },
            )
            for message, sender in messages
        )
        items.extend(
            (
                follow.created_at,
                {
                    "id": f"follow:{follow.id}",
                    "type": "新关注",
                    "title": follower.display_name,
                    "body": "关注了你",
                    "time_label": format_time_label(follow.created_at),
                    # Follow 模型当前没有已读字段，先作为历史通知展示；
                    # 可持久化的未读状态由 DirectMessage 提供。
                    "unread": False,
                },
            )
            for follow, follower in follows
        )
        items.sort(key=lambda item: item[0], reverse=True)
        return [item for _, item in items[:50]]

    def mark_notifications_read(self, user_id: int) -> None:
        self.db.execute(
            update(DirectMessage)
            .where(
                DirectMessage.recipient_id == user_id,
                DirectMessage.is_read.is_(False),
            )
            .values(is_read=True)
        )
        self.db.commit()

    def list_following(self, user_id: int) -> list[dict[str, int | str]]:
        rows = self.db.execute(
            select(User)
            .join(Follow, Follow.followed_id == User.id)
            .where(Follow.follower_id == user_id)
            .order_by(desc(Follow.created_at))
        ).scalars().all()
        return [
            {
                "id": user.id,
                "username": user.username,
                "display_name": user.display_name,
            }
            for user in rows
        ]

    def search(self, query: str) -> dict[str, list[dict[str, int | str]]]:
        """跨用户、直播间和动态做一次受限搜索，供搜索页统一展示。"""
        keyword = f"%{query.strip()}%"
        users = self.db.scalars(
            select(User)
            .where(
                User.is_active.is_(True),
                or_(User.username.ilike(keyword), User.display_name.ilike(keyword)),
            )
            .order_by(User.display_name)
            .limit(20)
        ).all()
        rooms = self.db.scalars(
            select(LiveRoom)
            .where(
                LiveRoom.status == "living",
                or_(LiveRoom.title.ilike(keyword), LiveRoom.anchor_name.ilike(keyword)),
            )
            .order_by(desc(LiveRoom.created_at))
            .limit(20)
        ).all()
        posts = self.db.execute(
            select(FeedPost, User)
            .join(User, User.id == FeedPost.author_id)
            .where(or_(FeedPost.body.ilike(keyword), User.display_name.ilike(keyword)))
            .order_by(desc(FeedPost.created_at))
            .limit(20)
        ).all()
        return {
            "users": [
                {
                    "id": user.id,
                    "username": user.username,
                    "display_name": user.display_name,
                }
                for user in users
            ],
            "rooms": [
                {
                    "id": room.id,
                    "title": room.title,
                    "anchor_name": room.anchor_name,
                    "online_count": room.online_count,
                    "status": room.status,
                    "category": room.category,
                }
                for room in rooms
            ],
            "posts": [
                {
                    "id": post.id,
                    "author": author.display_name,
                    "body": post.body,
                    "time_label": format_time_label(post.created_at),
                }
                for post, author in posts
            ],
        }

    def send_message(self, sender_id: int, recipient_id: int, body: str) -> DirectMessage:
        message = DirectMessage(
            sender_id=sender_id,
            recipient_id=recipient_id,
            body=body.strip(),
            is_read=False,
            created_at=datetime.utcnow(),
        )
        self.db.add(message)
        self.db.commit()
        self.db.refresh(message)
        return message

    def toggle_room_follow(self, room_id: int, user_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(LiveRoomFollow).where(
                LiveRoomFollow.room_id == room_id,
                LiveRoomFollow.user_id == user_id,
            )
        )
        if existing is None:
            self.db.add(LiveRoomFollow(room_id=room_id, user_id=user_id, created_at=datetime.utcnow()))
            active = True
        else:
            self.db.delete(existing)
            active = False
        self.db.commit()
        count = self.db.scalar(
            select(func.count()).select_from(LiveRoomFollow).where(LiveRoomFollow.room_id == room_id)
        ) or 0
        return active, int(count)

    def toggle_room_like(self, room_id: int, user_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(LiveRoomLike).where(
                LiveRoomLike.room_id == room_id,
                LiveRoomLike.user_id == user_id,
            )
        )
        if existing is None:
            self.db.add(LiveRoomLike(room_id=room_id, user_id=user_id, created_at=datetime.utcnow()))
            active = True
        else:
            self.db.delete(existing)
            active = False
        self.db.commit()
        count = self.db.scalar(
            select(func.count()).select_from(LiveRoomLike).where(LiveRoomLike.room_id == room_id)
        ) or 0
        return active, int(count)

    def get_room_interaction_state(
        self,
        room_id: int,
        user_id: int | None,
    ) -> dict[str, bool | int]:
        """返回直播间详情需要的关注/点赞快照。

        详情页首次打开时不能只依赖按钮的本地默认值，否则用户重新进入同一
        房间会看到“关注”和“点赞 0”。这里把当前用户关系和全局点赞数一次读出，
        Flutter 端即可直接恢复上次的交互状态。
        """
        following = False
        liked = False
        if user_id is not None:
            following = (
                self.db.scalar(
                    select(LiveRoomFollow).where(
                        LiveRoomFollow.room_id == room_id,
                        LiveRoomFollow.user_id == user_id,
                    )
                )
                is not None
            )
            liked = (
                self.db.scalar(
                    select(LiveRoomLike).where(
                        LiveRoomLike.room_id == room_id,
                        LiveRoomLike.user_id == user_id,
                    )
                )
                is not None
            )
        like_count = self.db.scalar(
            select(func.count()).select_from(LiveRoomLike).where(
                LiveRoomLike.room_id == room_id
            )
        ) or 0
        return {
            "following": following,
            "liked": liked,
            "like_count": int(like_count),
        }
