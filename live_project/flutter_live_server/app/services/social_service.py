from __future__ import annotations

from app.core.exceptions import AppException, NotFoundException
from app.models.file import FileRecord
from app.models.live_room import LiveRoom
from app.models.user import User
from app.repositories.social_repository import SocialRepository
from app.schemas.social import (
    CreateFeedCommentRequest,
    CreateFeedPostRequest,
    DirectMessageResponse,
    FeedCommentResponse,
    FeedMediaResponse,
    FeedPostResponse,
    FollowedUserResponse,
    MessageConversationResponse,
    MessageMediaResponse,
    MessageSendRequest,
    NotificationResponse,
    ProfileResponse,
    PublicFeedProfileResponse,
    SearchResponse,
    ToggleInteractionResponse,
    format_time_label,
)
from app.services.oss_service import OSSService


class SocialService:
    """Phase 2 的业务规则层。

    这里负责把数据库对象组合成对客户端稳定的 DTO，并在互动前确认目标
    动态或直播间存在；数据库查询和幂等细节仍留给 Repository。
    """

    def __init__(self, repository: SocialRepository, oss: OSSService) -> None:
        self.repository = repository
        self.oss = oss

    def list_posts(self, tab: str, user: User) -> list[FeedPostResponse]:
        return [
            self._post_response(post, author, liked, media, comments, user.id)
            for post, author, liked, media, comments in self.repository.list_posts(tab, user.id)
        ]

    def create_post(self, payload: CreateFeedPostRequest, user: User) -> FeedPostResponse:
        body = payload.body.strip()
        file_ids = payload.file_ids
        if not body and not file_ids:
            raise AppException("请填写动态内容或选择媒体", 40050, 400)
        if len(file_ids) != len(set(file_ids)):
            raise AppException("媒体文件不能重复", 40051, 400)

        files_by_id = self.repository.files_by_ids(file_ids)
        if len(files_by_id) != len(file_ids):
            raise NotFoundException("媒体文件不存在", 40442)
        files = [files_by_id[file_id] for file_id in file_ids]
        for file in files:
            if file.user_id != user.id:
                raise AppException("无权使用该媒体文件", 40341, 403)
            if file.status != "active":
                raise AppException("媒体文件尚未完成上传或已删除", 40052, 400)
            if file.category not in {"image", "video"}:
                raise AppException("动态仅支持图片或视频", 40053, 400)

        media_types = {file.category for file in files}
        if "video" in media_types and len(files) != 1:
            raise AppException("视频动态只能选择一个视频", 40054, 400)
        media = [(file, file.category) for file in files]
        post = self.repository.create_post(author_id=user.id, body=body, media=media)
        return self._post_response(
            post, user, False, self.repository.post_media(post.id), [], user.id
        )

    def get_post(self, post_id: int, user: User) -> FeedPostResponse:
        result = self.repository.get_post(post_id, user.id)
        if result is None:
            raise NotFoundException("动态不存在", 40411)
        post, author, liked, media, comments = result
        return self._post_response(post, author, liked, media, comments, user.id)

    def list_comments(self, post_id: int, user: User) -> list[FeedCommentResponse]:
        self.get_post(post_id, user)
        return [
            self._comment_response(comment, author)
            for comment, author in self.repository.list_comments(post_id)
        ]

    def create_comment(
        self, post_id: int, payload: CreateFeedCommentRequest, user: User
    ) -> FeedCommentResponse:
        result = self.repository.get_post(post_id, user.id)
        if result is None:
            raise NotFoundException("动态不存在", 40411)
        body = payload.body.strip()
        if not body:
            raise AppException("评论内容不能为空", 40056, 400)
        comment = self.repository.create_comment(result[0], user.id, body)
        return self._comment_response(comment, user)

    def delete_post(self, post_id: int, user: User) -> None:
        result = self.repository.get_post(post_id, user.id)
        if result is None:
            raise NotFoundException("动态不存在", 40411)
        post, _, _, media, _ = result
        if post.author_id != user.id:
            raise AppException("只能删除自己发布的动态", 40342, 403)
        files = [file for _, file in media]
        for file in files:
            self.oss.delete_object(file.object_key)
        self.repository.delete_post(post, files)

    def public_feed_profile(self, user_id: int, viewer: User) -> PublicFeedProfileResponse:
        result = self.repository.get_public_feed_profile(user_id, viewer.id)
        if result is None:
            raise NotFoundException("用户不存在", 40412)
        target, stats, posts = result
        return PublicFeedProfileResponse(
            id=target.id,
            username=target.username,
            display_name=target.display_name,
            following_count=stats["following_count"],
            follower_count=stats["follower_count"],
            post_count=stats["post_count"],
            following=stats["following"],
            is_self=target.id == viewer.id,
            posts=[
                self._post_response(post, author, liked, media, comments, viewer.id)
                for post, author, liked, media, comments in posts
            ],
        )

    def toggle_user_follow(self, user_id: int, viewer: User) -> ToggleInteractionResponse:
        if user_id == viewer.id:
            raise AppException("不能关注自己", 40055, 400)
        target = self.repository.db.get(User, user_id)
        if target is None or not target.is_active:
            raise NotFoundException("用户不存在", 40412)
        active, count = self.repository.toggle_user_follow(target, viewer.id)
        return ToggleInteractionResponse(active=active, count=count)

    def _post_response(
        self,
        post,
        author: User,
        liked: bool,
        media: list[tuple[object, FileRecord]],
        comments: list[tuple[object, User]],
        viewer_id: int,
    ) -> FeedPostResponse:
        return FeedPostResponse(
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
            media=[
                FeedMediaResponse(
                    file_id=file.id,
                    media_type=link.media_type,
                    url=self.oss.generate_download_url(file.object_key),
                )
                for link, file in media
            ],
            comments_preview=[
                self._comment_response(comment, comment_author)
                for comment, comment_author in comments
            ],
            can_delete=post.author_id == viewer_id,
        )

    def _comment_response(self, comment, author: User) -> FeedCommentResponse:
        return FeedCommentResponse(
            id=comment.id,
            author_id=author.id,
            author=author.display_name,
            body=comment.body,
            time_label=format_time_label(comment.created_at),
        )

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

    def send_message(self, payload: MessageSendRequest, user: User) -> DirectMessageResponse:
        """发送文字、图片或视频私信；附件必须由发送者上传并确认。"""
        recipient = self.repository.db.get(User, payload.recipient_id)
        if recipient is None or not recipient.is_active:
            raise NotFoundException(message="接收用户不存在", code=40412)
        if recipient.id == user.id:
            raise AppException("不能给自己发送私信", 40057, 400)
        body = payload.body.strip()
        if len(payload.file_ids) != len(set(payload.file_ids)):
            raise AppException("媒体文件不能重复", 40051, 400)
        files_by_id = self.repository.files_by_ids(payload.file_ids)
        if len(files_by_id) != len(payload.file_ids):
            raise NotFoundException("媒体文件不存在", 40442)
        files = [files_by_id[file_id] for file_id in payload.file_ids]
        for file in files:
            if file.user_id != user.id:
                raise AppException("无权使用该媒体文件", 40341, 403)
            if file.status != "active":
                raise AppException("媒体文件尚未完成上传或已删除", 40052, 400)
            if file.category not in {"image", "video"}:
                raise AppException("私信仅支持图片或视频", 40058, 400)
        media_types = {file.category for file in files}
        if "video" in media_types and len(files) != 1:
            raise AppException("视频私信只能发送一个视频", 40059, 400)
        if not body and not files:
            raise AppException("请填写消息或选择媒体", 40060, 400)
        message = self.repository.send_message(
            user.id,
            recipient.id,
            body,
            [(file, file.category) for file in files],
        )
        return self._message_response(message, self.repository.message_media(message.id), user.id)

    def conversation(self, other_user_id: int, user: User) -> list[DirectMessageResponse]:
        other = self.repository.db.get(User, other_user_id)
        if other is None or not other.is_active:
            raise NotFoundException(message="会话用户不存在", code=40412)
        if other.id == user.id:
            raise AppException("不能打开与自己的私信", 40057, 400)
        messages = self.repository.list_direct_messages(user.id, other.id)
        self.repository.mark_conversation_read(user.id, other.id)
        return [self._message_response(message, media, user.id) for message, media in messages]

    def _message_response(
        self, message, media: list[tuple[object, FileRecord]], viewer_id: int
    ) -> DirectMessageResponse:
        return DirectMessageResponse(
            id=message.id,
            sender_id=message.sender_id,
            recipient_id=message.recipient_id,
            body=message.body,
            is_mine=message.sender_id == viewer_id,
            time_label=format_time_label(message.created_at),
            media=[
                MessageMediaResponse(
                    file_id=file.id,
                    media_type=link.media_type,
                    url=self.oss.generate_download_url(file.object_key),
                )
                for link, file in media
            ],
        )

    def mark_conversation_read(self, user: User, other_user_id: int) -> None:
        self.repository.mark_conversation_read(user.id, other_user_id)

    def notifications(self, user: User) -> list[NotificationResponse]:
        return [
            NotificationResponse(**item) for item in self.repository.list_notifications(user.id)
        ]

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
