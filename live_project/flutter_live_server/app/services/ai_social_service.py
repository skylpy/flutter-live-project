"""虚拟居民在私信与动态社区中的低频、有上下文互动。"""

from __future__ import annotations

import asyncio
import hashlib
import logging
from datetime import datetime, timezone

from sqlalchemy import desc, select

from app.core.config import Settings, settings
from app.core.database import SessionLocal
from app.models.ai import VirtualResidentProfile
from app.models.social import DirectMessage, FeedComment, FeedPost
from app.models.user import User
from app.repositories.social_repository import SocialRepository
from app.schemas.social import DirectMessageResponse, format_time_label
from app.services.ai_room_service import ChatLine, DeepSeekChatClient, Resident, choose_resident
from app.services.realtime_service import event_time, user_realtime_hub

logger = logging.getLogger(__name__)

_SOCIAL_MEDIA = (
    ("/static/ai_bots/rainy_cafe.jpg", "image"),
    ("/static/ai_bots/night_bus.jpg", "image"),
    ("/static/ai_bots/keyboard_night.jpg", "image"),
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _human_delay(minimum: float, maximum: float, cue: str) -> float:
    """按输入稳定地分散回复时间，避免机器人固定秒回。"""
    if maximum <= minimum:
        return minimum
    fraction = hashlib.blake2s(cue.encode(), digest_size=2).digest()
    return minimum + (int.from_bytes(fraction, "big") / 65535) * (maximum - minimum)


def _resident(user: User, profile: VirtualResidentProfile) -> Resident:
    return Resident(
        user_id=user.id,
        name=user.display_name,
        role=profile.role,
        persona=profile.persona,
        interests=profile.interests,
        speaking_style=profile.speaking_style,
    )


class VirtualSocialDirector:
    """私信、动态和评论的机器人导演。

    所有模型调用都发生在持久化真人行为之后；模型故障只跳过本次机器人互动，
    不影响真人的私信、发动态或评论提交。
    """

    def __init__(
        self,
        client: DeepSeekChatClient | None = None,
        config: Settings = settings,
    ) -> None:
        self._client = client or DeepSeekChatClient(config)
        self._config = config
        self._dm_pending: set[tuple[int, int]] = set()
        self._pending_lock = asyncio.Lock()

    async def on_human_direct_message(
        self, *, sender_id: int, recipient_id: int, message: str
    ) -> None:
        """向虚拟居民私信时稳定回应；短暂合并连续输入，避免逐条秒回。"""
        if not self._client.is_available:
            return
        key = (sender_id, recipient_id)
        async with self._pending_lock:
            if key in self._dm_pending:
                return
            self._dm_pending.add(key)
        try:
            await asyncio.sleep(
                _human_delay(
                    self._config.ai_bot_dm_min_delay_seconds,
                    self._config.ai_bot_dm_max_delay_seconds,
                    f"dm:{sender_id}:{recipient_id}:{message}",
                )
            )
            prepared = self._prepare_direct_reply(sender_id, recipient_id)
            if prepared is None:
                return
            human, resident, history, latest = prepared
            reply = await self._client.create_private_reply(
                resident=resident,
                counterpart_name=human.display_name,
                latest_message=latest,
                history=history,
            )
            if reply is None:
                return
            saved = self._save_direct_reply(
                human_id=human.id, resident_id=resident.user_id, body=reply
            )
            if saved is None:
                return
            await self._publish_direct_reply(human, resident, saved)
        except Exception:
            logger.exception("Virtual resident direct-message reply failed")
        finally:
            async with self._pending_lock:
                self._dm_pending.discard(key)

    async def on_human_post(self, *, post_id: int, author_id: int) -> None:
        """真人发布动态后，由一名匹配兴趣的居民做一次延迟首评。"""
        if not self._client.is_available:
            return
        try:
            await asyncio.sleep(
                _human_delay(
                    self._config.ai_bot_social_min_delay_seconds,
                    self._config.ai_bot_social_max_delay_seconds,
                    f"post:{post_id}:{author_id}",
                )
            )
            prepared = self._prepare_post_comment(post_id, author_id)
            if prepared is None:
                return
            post, author, resident = prepared
            reply = await self._client.create_comment_reply(
                resident=resident,
                post_author=author.display_name,
                post_body=post.body,
                counterpart_name=author.display_name,
                counterpart_comment="发布了一条动态",
                replying=False,
            )
            if reply is not None:
                self._save_comment(post_id, resident.user_id, reply, parent_id=None)
        except Exception:
            logger.exception("Virtual resident post comment failed")

    async def on_human_comment(self, *, post_id: int, comment_id: int) -> None:
        """机器人作者或被 @ 回复的机器人，对真人评论延迟接话。"""
        if not self._client.is_available:
            return
        try:
            await asyncio.sleep(
                _human_delay(
                    self._config.ai_bot_social_min_delay_seconds,
                    self._config.ai_bot_social_max_delay_seconds,
                    f"comment:{post_id}:{comment_id}",
                )
            )
            prepared = self._prepare_comment_reply(post_id, comment_id)
            if prepared is None:
                return
            post, post_author, comment, commenter, resident = prepared
            reply = await self._client.create_comment_reply(
                resident=resident,
                post_author=post_author.display_name,
                post_body=post.body,
                counterpart_name=commenter.display_name,
                counterpart_comment=comment.body,
                replying=True,
            )
            if reply is not None:
                self._save_comment(post_id, resident.user_id, reply, parent_id=comment.id)
        except Exception:
            logger.exception("Virtual resident comment reply failed")

    async def publish_post_if_due(self) -> None:
        """定时发布一条带受控媒体的居民动态，避免每次服务重启都刷屏。"""
        if not self._client.is_available:
            return
        prepared = self._prepare_scheduled_post()
        if prepared is None:
            return
        resident, media = prepared
        try:
            body = await self._client.create_post_caption(resident=resident)
            if body is not None:
                self._save_virtual_post(resident.user_id, body, media)
        except Exception:
            logger.exception("Virtual resident scheduled post failed")

    def _prepare_direct_reply(
        self, human_id: int, resident_id: int
    ) -> tuple[User, Resident, list[ChatLine], str] | None:
        with SessionLocal() as db:
            repository = SocialRepository(db)
            human = db.get(User, human_id)
            resident_user, profile = self._resident_profile(db, resident_id)
            if (
                human is None
                or not human.is_active
                or human.is_virtual
                or resident_user is None
                or profile is None
            ):
                return None
            rows = repository.recent_direct_messages(
                human.id, resident_user.id, limit=self._config.ai_bot_history_size
            )
            if not rows or rows[-1][0].sender_id != human.id:
                return None
            history = [
                ChatLine(
                    name=sender.display_name,
                    role=None,
                    body=message.body or "[图片或视频]",
                    is_virtual=sender.is_virtual,
                )
                for message, sender in rows
            ]
            return human, _resident(resident_user, profile), history, rows[-1][0].body

    def _prepare_post_comment(
        self, post_id: int, author_id: int
    ) -> tuple[FeedPost, User, Resident] | None:
        with SessionLocal() as db:
            post = db.get(FeedPost, post_id)
            author = db.get(User, author_id)
            if post is None or author is None or post.author_id != author_id or author.is_virtual:
                return None
            choices = [_resident(user, profile) for user, profile in self._enabled_residents(db)]
            resident = choose_resident(choices, room_id=post_id, cue=post.body)
            return (post, author, resident) if resident is not None else None

    def _prepare_comment_reply(
        self, post_id: int, comment_id: int
    ) -> tuple[FeedPost, User, FeedComment, User, Resident] | None:
        with SessionLocal() as db:
            comment = db.get(FeedComment, comment_id)
            post = db.get(FeedPost, post_id)
            if comment is None or post is None or comment.post_id != post.id:
                return None
            commenter = db.get(User, comment.author_id)
            post_author = db.get(User, post.author_id)
            if commenter is None or post_author is None or commenter.is_virtual:
                return None
            candidate_id = post.author_id if post_author.is_virtual else None
            if candidate_id is None and comment.parent_id is not None:
                parent = db.get(FeedComment, comment.parent_id)
                if parent is not None:
                    parent_author = db.get(User, parent.author_id)
                    if parent_author is not None and parent_author.is_virtual:
                        candidate_id = parent_author.id
            if candidate_id is None:
                return None
            resident_user, profile = self._resident_profile(db, candidate_id)
            if resident_user is None or profile is None:
                return None
            return post, post_author, comment, commenter, _resident(resident_user, profile)

    def _prepare_scheduled_post(self) -> tuple[Resident, tuple[str, str]] | None:
        with SessionLocal() as db:
            latest = db.scalar(
                select(FeedPost.created_at)
                .join(User, User.id == FeedPost.author_id)
                .where(User.is_virtual.is_(True))
                .order_by(desc(FeedPost.created_at))
                .limit(1)
            )
            if latest is not None:
                elapsed = (_utcnow() - latest).total_seconds() / 60
                if elapsed < self._config.ai_bot_social_post_interval_minutes:
                    return None
            choices = [_resident(user, profile) for user, profile in self._enabled_residents(db)]
            if not choices:
                return None
            index = int(datetime.now(timezone.utc).strftime("%H")) % len(choices)
            return choices[index], _SOCIAL_MEDIA[index % len(_SOCIAL_MEDIA)]

    @staticmethod
    def _resident_profile(db, user_id: int) -> tuple[User | None, VirtualResidentProfile | None]:
        row = db.execute(
            select(User, VirtualResidentProfile)
            .join(VirtualResidentProfile, VirtualResidentProfile.user_id == User.id)
            .where(
                User.id == user_id,
                User.is_active.is_(True),
                User.is_virtual.is_(True),
                VirtualResidentProfile.is_enabled.is_(True),
            )
        ).first()
        return row if row is not None else (None, None)

    @staticmethod
    def _enabled_residents(db) -> list[tuple[User, VirtualResidentProfile]]:
        return db.execute(
            select(User, VirtualResidentProfile)
            .join(VirtualResidentProfile, VirtualResidentProfile.user_id == User.id)
            .where(
                User.is_active.is_(True),
                User.is_virtual.is_(True),
                VirtualResidentProfile.is_enabled.is_(True),
            )
            .order_by(User.id.asc())
        ).all()

    @staticmethod
    def _save_direct_reply(*, human_id: int, resident_id: int, body: str) -> DirectMessage | None:
        with SessionLocal() as db:
            human = db.get(User, human_id)
            resident = db.get(User, resident_id)
            if human is None or resident is None or not resident.is_virtual:
                return None
            return SocialRepository(db).send_message(resident.id, human.id, body, [])

    @staticmethod
    def _save_comment(
        post_id: int, resident_id: int, body: str, *, parent_id: int | None
    ) -> FeedComment | None:
        with SessionLocal() as db:
            post = db.get(FeedPost, post_id)
            resident = db.get(User, resident_id)
            if post is None or resident is None or not resident.is_virtual:
                return None
            if parent_id is not None:
                parent = db.get(FeedComment, parent_id)
                if parent is None or parent.post_id != post.id:
                    return None
            return SocialRepository(db).create_comment(post, resident.id, body, parent_id=parent_id)

    @staticmethod
    def _save_virtual_post(resident_id: int, body: str, media: tuple[str, str]) -> FeedPost | None:
        with SessionLocal() as db:
            resident = db.get(User, resident_id)
            if resident is None or not resident.is_virtual or not resident.is_active:
                return None
            return SocialRepository(db).create_virtual_post(
                author_id=resident.id, body=body, media_sources=[media]
            )

    @staticmethod
    async def _publish_direct_reply(
        human: User, resident: Resident, message: DirectMessage
    ) -> None:
        payload = DirectMessageResponse(
            id=message.id,
            sender_id=resident.user_id,
            recipient_id=human.id,
            body=message.body,
            is_mine=False,
            time_label=format_time_label(message.created_at),
            media=[],
            is_virtual=True,
        )
        await user_realtime_hub.publish(
            human.id,
            {
                "type": "notification",
                "event": "message",
                "notification": {
                    "id": f"message:{message.id}",
                    "type": "互动消息",
                    "title": f"{resident.name} · 虚拟居民",
                    "body": message.body,
                    "timeLabel": "刚刚",
                    "unread": True,
                },
                "message": payload.model_dump(by_alias=True),
                "sentAt": event_time(message.created_at),
            },
        )


social_bot_director = VirtualSocialDirector()
