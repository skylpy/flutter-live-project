from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import and_, delete, desc, func, or_, select, update
from sqlalchemy.orm import Session, aliased

from app.models.file import FileRecord
from app.models.live_room import LiveRoom
from app.models.social import (
    DirectMessage,
    DirectMessageMedia,
    FeedComment,
    FeedLike,
    FeedPost,
    FeedPostMedia,
    Follow,
    LiveRoomFollow,
    LiveRoomLike,
)
from app.models.user import User
from app.schemas.social import format_time_label


def _utcnow() -> datetime:
    """数据库沿用无时区 UTC DateTime，避免本地时区混入排序和相对时间。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


class SocialRepository:
    """Phase 2 的统一数据访问层。

    路由和 Service 不直接拼 SQL。这样 Flutter Repository 后续改成缓存或分页时，
    服务端数据库查询仍然集中在此处，互动的唯一性也由数据库约束兜底。
    """

    def __init__(self, db: Session) -> None:
        self.db = db

    def list_posts(self, tab: str, user_id: int) -> list[tuple]:
        query = (
            select(FeedPost, User)
            .join(User, User.id == FeedPost.author_id)
            .order_by(desc(FeedPost.created_at))
        )
        if tab == "关注":
            query = query.join(Follow, Follow.followed_id == FeedPost.author_id).where(
                Follow.follower_id == user_id
            )
        return self._post_rows(self.db.execute(query).all(), user_id)

    def _post_rows(self, rows: list[tuple], user_id: int) -> list[tuple]:
        liked_ids = {
            row.post_id
            for row in self.db.scalars(select(FeedLike).where(FeedLike.user_id == user_id))
        }
        media_by_post = self._media_by_post([post.id for post, _ in rows])
        comments_by_post = self._comment_preview_by_post([post.id for post, _ in rows])
        return [
            (
                post,
                author,
                post.id in liked_ids,
                media_by_post.get(post.id, []),
                comments_by_post.get(post.id, []),
            )
            for post, author in rows
        ]

    def _media_by_post(
        self, post_ids: list[int]
    ) -> dict[int, list[tuple[FeedPostMedia, FileRecord | None]]]:
        if not post_ids:
            return {}
        rows = self.db.execute(
            select(FeedPostMedia, FileRecord)
            .outerjoin(FileRecord, FileRecord.id == FeedPostMedia.file_id)
            .where(FeedPostMedia.post_id.in_(post_ids))
            .order_by(FeedPostMedia.sort_order.asc())
        ).all()
        result: dict[int, list[tuple[FeedPostMedia, FileRecord]]] = {}
        for media, file in rows:
            result.setdefault(media.post_id, []).append((media, file))
        return result

    def files_by_ids(self, file_ids: list[int]) -> dict[int, FileRecord]:
        if not file_ids:
            return {}
        return {
            file.id: file
            for file in self.db.scalars(select(FileRecord).where(FileRecord.id.in_(file_ids)))
        }

    def create_post(
        self,
        *,
        author_id: int,
        body: str,
        media: list[tuple[FileRecord, str]],
    ) -> FeedPost:
        media_kind = "none" if not media else media[0][1]
        post = FeedPost(
            author_id=author_id,
            body=body,
            media_kind=media_kind,
            likes_count=0,
            comments_count=0,
            shares_count=0,
            created_at=_utcnow(),
            updated_at=_utcnow(),
        )
        self.db.add(post)
        self.db.flush()
        for order, (file, media_type) in enumerate(media):
            self.db.add(
                FeedPostMedia(
                    post_id=post.id,
                    file_id=file.id,
                    media_type=media_type,
                    sort_order=order,
                    created_at=_utcnow(),
                )
            )
        self.db.commit()
        self.db.refresh(post)
        return post

    def create_virtual_post(
        self,
        *,
        author_id: int,
        body: str,
        media_sources: list[tuple[str, str]],
    ) -> FeedPost:
        """创建仅由服务端受控静态媒体组成的虚拟居民动态。"""
        post = FeedPost(
            author_id=author_id,
            body=body,
            media_kind=media_sources[0][1] if media_sources else "none",
            likes_count=0,
            comments_count=0,
            shares_count=0,
            created_at=_utcnow(),
            updated_at=_utcnow(),
        )
        self.db.add(post)
        self.db.flush()
        for order, (source_url, media_type) in enumerate(media_sources):
            self.db.add(
                FeedPostMedia(
                    post_id=post.id,
                    file_id=None,
                    source_url=source_url,
                    media_type=media_type,
                    sort_order=order,
                    created_at=_utcnow(),
                )
            )
        self.db.commit()
        self.db.refresh(post)
        return post

    def post_media(self, post_id: int) -> list[tuple[FeedPostMedia, FileRecord]]:
        return self._media_by_post([post_id]).get(post_id, [])

    def _comment_preview_by_post(
        self, post_ids: list[int]
    ) -> dict[int, list[tuple[FeedComment, User, User | None]]]:
        if not post_ids:
            return {}
        parent_comment = aliased(FeedComment)
        reply_author = aliased(User)
        rows = self.db.execute(
            select(FeedComment, User, reply_author)
            .join(User, User.id == FeedComment.author_id)
            .outerjoin(parent_comment, FeedComment.parent_id == parent_comment.id)
            .outerjoin(reply_author, reply_author.id == parent_comment.author_id)
            .where(FeedComment.post_id.in_(post_ids))
            .order_by(FeedComment.post_id, desc(FeedComment.created_at), desc(FeedComment.id))
        ).all()
        grouped: dict[int, list[tuple[FeedComment, User, User | None]]] = {}
        for comment, author, target_author in rows:
            comments = grouped.setdefault(comment.post_id, [])
            if len(comments) < 3:
                comments.append((comment, author, target_author))
        for comments in grouped.values():
            comments.reverse()
        return grouped

    def get_post(self, post_id: int, user_id: int) -> tuple | None:
        row = self.db.execute(
            select(FeedPost, User)
            .join(User, User.id == FeedPost.author_id)
            .where(FeedPost.id == post_id)
        ).first()
        if row is None:
            return None
        return self._post_rows([row], user_id)[0]

    def list_comments(self, post_id: int) -> list[tuple[FeedComment, User, User | None]]:
        parent_comment = aliased(FeedComment)
        reply_author = aliased(User)
        return self.db.execute(
            select(FeedComment, User, reply_author)
            .join(User, User.id == FeedComment.author_id)
            .outerjoin(parent_comment, FeedComment.parent_id == parent_comment.id)
            .outerjoin(reply_author, reply_author.id == parent_comment.author_id)
            .where(FeedComment.post_id == post_id)
            .order_by(FeedComment.created_at.asc(), FeedComment.id.asc())
        ).all()

    def create_comment(
        self,
        post: FeedPost,
        author_id: int,
        body: str,
        *,
        parent_id: int | None = None,
    ) -> FeedComment:
        comment = FeedComment(
            post_id=post.id,
            author_id=author_id,
            body=body,
            parent_id=parent_id,
            created_at=_utcnow(),
        )
        self.db.add(comment)
        post.comments_count += 1
        post.updated_at = _utcnow()
        self.db.commit()
        self.db.refresh(comment)
        return comment

    def get_comment(self, comment_id: int) -> FeedComment | None:
        return self.db.get(FeedComment, comment_id)

    def recent_direct_messages(
        self, user_id: int, other_user_id: int, *, limit: int
    ) -> list[tuple[DirectMessage, User]]:
        rows = self.db.execute(
            select(DirectMessage, User)
            .join(User, User.id == DirectMessage.sender_id)
            .where(
                or_(
                    and_(
                        DirectMessage.sender_id == user_id,
                        DirectMessage.recipient_id == other_user_id,
                    ),
                    and_(
                        DirectMessage.sender_id == other_user_id,
                        DirectMessage.recipient_id == user_id,
                    ),
                )
            )
            .order_by(desc(DirectMessage.created_at), desc(DirectMessage.id))
            .limit(limit)
        ).all()
        return list(reversed(rows))

    def get_public_feed_profile(
        self, user_id: int, viewer_id: int
    ) -> tuple[User, dict, list[tuple]] | None:
        target = self.db.get(User, user_id)
        if target is None or not target.is_active:
            return None
        following_count = (
            self.db.scalar(
                select(func.count()).select_from(Follow).where(Follow.follower_id == target.id)
            )
            or 0
        )
        follower_count = (
            self.db.scalar(
                select(func.count()).select_from(Follow).where(Follow.followed_id == target.id)
            )
            or 0
        )
        post_count = (
            self.db.scalar(
                select(func.count()).select_from(FeedPost).where(FeedPost.author_id == target.id)
            )
            or 0
        )
        following = (
            self.db.scalar(
                select(Follow.id).where(
                    Follow.follower_id == viewer_id, Follow.followed_id == target.id
                )
            )
            is not None
        )
        posts = self._post_rows(
            self.db.execute(
                select(FeedPost, User)
                .join(User, User.id == FeedPost.author_id)
                .where(FeedPost.author_id == target.id)
                .order_by(desc(FeedPost.created_at))
            ).all(),
            viewer_id,
        )
        return (
            target,
            {
                "following_count": int(following_count),
                "follower_count": int(follower_count),
                "post_count": int(post_count),
                "following": following,
            },
            posts,
        )

    def toggle_user_follow(self, target: User, viewer_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(Follow).where(Follow.follower_id == viewer_id, Follow.followed_id == target.id)
        )
        if existing is None:
            self.db.add(Follow(follower_id=viewer_id, followed_id=target.id, created_at=_utcnow()))
            active = True
        else:
            self.db.delete(existing)
            active = False
        self.db.commit()
        count = (
            self.db.scalar(
                select(func.count()).select_from(Follow).where(Follow.followed_id == target.id)
            )
            or 0
        )
        return active, int(count)

    def delete_post(self, post: FeedPost, media_files: list[FileRecord]) -> None:
        for file in media_files:
            file.status = "deleted"
            file.deleted_at = file.updated_at = _utcnow()
        # 数据库生产环境有 ON DELETE CASCADE，但这里显式清理关联关系，保证
        # SQLite 测试环境和未来的迁移场景都不会留下失效的动态关联记录。
        self.db.execute(delete(FeedComment).where(FeedComment.post_id == post.id))
        self.db.execute(delete(FeedLike).where(FeedLike.post_id == post.id))
        self.db.execute(delete(FeedPostMedia).where(FeedPostMedia.post_id == post.id))
        self.db.delete(post)
        self.db.commit()

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
            self.db.add(FeedLike(post_id=post_id, user_id=user_id, created_at=_utcnow()))
            post.likes_count += 1
            active = True
        else:
            self.db.delete(existing)
            post.likes_count = max(0, post.likes_count - 1)
            active = False
        self.db.commit()
        return active, post.likes_count

    def get_profile(self, user: User) -> dict[str, int | str]:
        following = (
            self.db.scalar(
                select(func.count()).select_from(Follow).where(Follow.follower_id == user.id)
            )
            or 0
        )
        followers = (
            self.db.scalar(
                select(func.count()).select_from(Follow).where(Follow.followed_id == user.id)
            )
            or 0
        )
        liked = (
            self.db.scalar(
                select(func.coalesce(func.sum(FeedPost.likes_count), 0))
                .select_from(FeedPost)
                .where(FeedPost.author_id == user.id)
            )
            or 0
        )
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
        user.updated_at = _utcnow()
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
        users = {user.id: user for user in self.db.scalars(select(User).where(User.id.in_(latest)))}
        media_types = {
            message_id: media_type
            for message_id, media_type in self.db.execute(
                select(DirectMessageMedia.message_id, DirectMessageMedia.media_type).where(
                    DirectMessageMedia.message_id.in_([message.id for message in latest.values()])
                )
            )
        }
        return [
            {
                "user_id": other_id,
                "user_name": users[other_id].display_name if other_id in users else "用户",
                "preview": message.body
                or ("[视频]" if media_types.get(message.id) == "video" else "[图片]"),
                "time_label": format_time_label(message.created_at),
                "unread": unread.get(other_id, 0),
            }
            for other_id, message in latest.items()
        ]

    def list_direct_messages(
        self, user_id: int, other_user_id: int
    ) -> list[tuple[DirectMessage, list[tuple[DirectMessageMedia, FileRecord]]]]:
        messages = self.db.scalars(
            select(DirectMessage)
            .where(
                or_(
                    and_(
                        DirectMessage.sender_id == user_id,
                        DirectMessage.recipient_id == other_user_id,
                    ),
                    and_(
                        DirectMessage.sender_id == other_user_id,
                        DirectMessage.recipient_id == user_id,
                    ),
                )
            )
            .order_by(DirectMessage.created_at.asc(), DirectMessage.id.asc())
            .limit(200)
        ).all()
        media_by_message = self._direct_media_by_message([message.id for message in messages])
        return [(message, media_by_message.get(message.id, [])) for message in messages]

    def _direct_media_by_message(
        self, message_ids: list[int]
    ) -> dict[int, list[tuple[DirectMessageMedia, FileRecord]]]:
        if not message_ids:
            return {}
        rows = self.db.execute(
            select(DirectMessageMedia, FileRecord)
            .join(FileRecord, FileRecord.id == DirectMessageMedia.file_id)
            .where(DirectMessageMedia.message_id.in_(message_ids))
            .order_by(DirectMessageMedia.sort_order.asc())
        ).all()
        grouped: dict[int, list[tuple[DirectMessageMedia, FileRecord]]] = {}
        for link, file in rows:
            grouped.setdefault(link.message_id, []).append((link, file))
        return grouped

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
        rows = (
            self.db.execute(
                select(User)
                .join(Follow, Follow.followed_id == User.id)
                .where(Follow.follower_id == user_id)
                .order_by(desc(Follow.created_at))
            )
            .scalars()
            .all()
        )
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

    def send_message(
        self,
        sender_id: int,
        recipient_id: int,
        body: str,
        media: list[tuple[FileRecord, str]],
    ) -> DirectMessage:
        message = DirectMessage(
            sender_id=sender_id,
            recipient_id=recipient_id,
            body=body.strip(),
            is_read=False,
            created_at=_utcnow(),
        )
        self.db.add(message)
        self.db.flush()
        for order, (file, media_type) in enumerate(media):
            self.db.add(
                DirectMessageMedia(
                    message_id=message.id,
                    file_id=file.id,
                    media_type=media_type,
                    sort_order=order,
                    created_at=_utcnow(),
                )
            )
        self.db.commit()
        self.db.refresh(message)
        return message

    def message_media(self, message_id: int) -> list[tuple[DirectMessageMedia, FileRecord]]:
        return self._direct_media_by_message([message_id]).get(message_id, [])

    def toggle_room_follow(self, room_id: int, user_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(LiveRoomFollow).where(
                LiveRoomFollow.room_id == room_id,
                LiveRoomFollow.user_id == user_id,
            )
        )
        if existing is None:
            self.db.add(LiveRoomFollow(room_id=room_id, user_id=user_id, created_at=_utcnow()))
            active = True
        else:
            self.db.delete(existing)
            active = False
        self.db.commit()
        count = (
            self.db.scalar(
                select(func.count())
                .select_from(LiveRoomFollow)
                .where(LiveRoomFollow.room_id == room_id)
            )
            or 0
        )
        return active, int(count)

    def toggle_room_like(self, room_id: int, user_id: int) -> tuple[bool, int]:
        existing = self.db.scalar(
            select(LiveRoomLike).where(
                LiveRoomLike.room_id == room_id,
                LiveRoomLike.user_id == user_id,
            )
        )
        if existing is None:
            self.db.add(LiveRoomLike(room_id=room_id, user_id=user_id, created_at=_utcnow()))
            active = True
        else:
            self.db.delete(existing)
            active = False
        self.db.commit()
        count = (
            self.db.scalar(
                select(func.count())
                .select_from(LiveRoomLike)
                .where(LiveRoomLike.room_id == room_id)
            )
            or 0
        )
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
        like_count = (
            self.db.scalar(
                select(func.count())
                .select_from(LiveRoomLike)
                .where(LiveRoomLike.room_id == room_id)
            )
            or 0
        )
        return {
            "following": following,
            "liked": liked,
            "like_count": int(like_count),
        }
