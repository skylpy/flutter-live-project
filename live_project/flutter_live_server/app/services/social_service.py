from __future__ import annotations

from app.core.exceptions import NotFoundException
from app.models.live_room import LiveRoom
from app.models.user import User
from app.repositories.social_repository import SocialRepository
from app.schemas.social import (
    FollowedUserResponse,
    FeedPostResponse,
    MessageConversationResponse,
    MessageSendRequest,
    NotificationResponse,
    ProfileResponse,
    SearchResponse,
    ToggleInteractionResponse,
    format_time_label,
)


class SocialService:
    """Phase 2 的业务规则层。

    这里负责把数据库对象组合成对客户端稳定的 DTO，并在互动前确认目标
    动态或直播间存在；数据库查询和幂等细节仍留给 Repository。
    """

    def __init__(self, repository: SocialRepository) -> None:
        self.repository = repository

    def list_posts(self, tab: str, user: User) -> list[FeedPostResponse]:
        return [
            FeedPostResponse(
                id=post.id,
                author_id=post.author_id,
                author=author.display_name,
                body=post.body,
                time_label=format_time_label(post.created_at),
                likes=post.likes_count,
                comments=post.comments_count,
                shares=post.shares_count,
                liked=liked,
                media_kind=post.media_kind,
            )
            for post, author, liked in self.repository.list_posts(tab, user.id)
        ]

    def toggle_feed_like(self, post_id: int, user: User) -> ToggleInteractionResponse:
        active, count = self.repository.toggle_feed_like(post_id, user.id)
        if count == 0 and not active:
            raise NotFoundException(message="动态不存在", code=40411)
        return ToggleInteractionResponse(active=active, count=count)

    def profile(self, user: User) -> ProfileResponse:
        return ProfileResponse(**self.repository.get_profile(user))

    def update_profile(self, user: User, display_name: str) -> ProfileResponse:
        updated = self.repository.update_profile(user, display_name)
        return self.profile(updated)

    def conversations(self, user: User) -> list[MessageConversationResponse]:
        return [
            MessageConversationResponse(**item)
            for item in self.repository.list_conversations(user.id)
        ]

    def send_message(self, payload: MessageSendRequest, user: User) -> dict[str, int | str]:
        """发送私信前确认接收人存在，避免留下指向不存在用户的脏数据。"""
        recipient = self.repository.db.get(User, payload.recipient_id)
        if recipient is None or not recipient.is_active:
            raise NotFoundException(message="接收用户不存在", code=40412)
        message = self.repository.send_message(user.id, recipient.id, payload.body)
        return {"id": message.id, "body": message.body}

    def mark_conversation_read(self, user: User, other_user_id: int) -> None:
        self.repository.mark_conversation_read(user.id, other_user_id)

    def notifications(self, user: User) -> list[NotificationResponse]:
        return [NotificationResponse(**item) for item in self.repository.list_notifications(user.id)]

    def mark_notifications_read(self, user: User) -> None:
        self.repository.mark_notifications_read(user.id)

    def following(self, user: User) -> list[FollowedUserResponse]:
        return [FollowedUserResponse(**item) for item in self.repository.list_following(user.id)]

    def search(self, query: str) -> SearchResponse:
        return SearchResponse(**self.repository.search(query))

    def toggle_room_follow(self, room: LiveRoom, user: User) -> ToggleInteractionResponse:
        active, count = self.repository.toggle_room_follow(room.id, user.id)
        return ToggleInteractionResponse(active=active, count=count)

    def toggle_room_like(self, room: LiveRoom, user: User) -> ToggleInteractionResponse:
        active, count = self.repository.toggle_room_like(room.id, user.id)
        return ToggleInteractionResponse(active=active, count=count)

    def room_interaction_state(
        self,
        room_id: int,
        user_id: int | None,
    ) -> dict[str, bool | int]:
        """组装直播间详情进入时需要的互动状态快照。"""
        return self.repository.get_room_interaction_state(room_id, user_id)
