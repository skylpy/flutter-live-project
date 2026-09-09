from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field


class FeedMediaResponse(BaseModel):
    """一条动态媒体的即时展示信息。URL 不会写入数据库。"""

    model_config = ConfigDict(populate_by_name=True)

    file_id: int = Field(serialization_alias="fileId")
    media_type: str = Field(serialization_alias="mediaType")
    url: str


class FeedCommentResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: int
    author_id: int = Field(serialization_alias="authorId")
    author: str
    body: str
    time_label: str = Field(serialization_alias="timeLabel")


class FeedPostResponse(BaseModel):
    """动态列表项；作者资料和互动状态一次返回，页面无需再发 N+1 请求。"""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    author_id: int = Field(serialization_alias="authorId")
    author: str
    body: str
    time_label: str = Field(serialization_alias="timeLabel")
    likes: int
    comments: int
    shares: int
    liked: bool
    media_kind: str = Field(serialization_alias="mediaKind")
    media: list[FeedMediaResponse] = Field(default_factory=list)
    comments_preview: list[FeedCommentResponse] = Field(
        default_factory=list, serialization_alias="commentsPreview"
    )
    can_delete: bool = Field(default=False, serialization_alias="canDelete")


class CreateFeedPostRequest(BaseModel):
    """客户端只提交正文和自己已完成上传的文件 ID。"""

    body: str = Field(default="", max_length=2000)
    file_ids: list[int] = Field(
        default_factory=list,
        max_length=9,
    )


class CreateFeedCommentRequest(BaseModel):
    body: str = Field(min_length=1, max_length=500)


class PublicFeedProfileResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: int
    username: str
    display_name: str = Field(serialization_alias="displayName")
    following_count: int = Field(serialization_alias="followingCount")
    follower_count: int = Field(serialization_alias="followerCount")
    post_count: int = Field(serialization_alias="postCount")
    following: bool
    is_self: bool = Field(serialization_alias="isSelf")
    posts: list[FeedPostResponse]


class ToggleInteractionResponse(BaseModel):
    """关注或点赞操作后的统一结果。"""

    active: bool
    count: int


class MessageConversationResponse(BaseModel):
    """消息中心的一行会话摘要。"""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    user_id: int = Field(serialization_alias="userId")
    user_name: str = Field(serialization_alias="userName")
    preview: str
    time_label: str = Field(serialization_alias="timeLabel")
    unread: int


class MessageMediaResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    file_id: int = Field(serialization_alias="fileId")
    media_type: str = Field(serialization_alias="mediaType")
    url: str


class DirectMessageResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: int
    sender_id: int = Field(serialization_alias="senderId")
    recipient_id: int = Field(serialization_alias="recipientId")
    body: str
    is_mine: bool = Field(serialization_alias="isMine")
    time_label: str = Field(serialization_alias="timeLabel")
    media: list[MessageMediaResponse] = Field(default_factory=list)


class NotificationResponse(BaseModel):
    """消息中心顶部通知流的统一条目。"""

    id: str
    type: str
    title: str
    body: str
    time_label: str = Field(serialization_alias="timeLabel")
    unread: bool


class FollowedUserResponse(BaseModel):
    """当前用户关注的用户；用于关注列表和资料跳转。"""

    id: int
    username: str
    display_name: str = Field(serialization_alias="displayName")


class SearchUserResponse(BaseModel):
    id: int
    username: str
    display_name: str = Field(serialization_alias="displayName")


class SearchRoomResponse(BaseModel):
    id: int
    title: str
    anchor_name: str = Field(serialization_alias="anchorName")
    online_count: int = Field(serialization_alias="onlineCount")
    status: str
    category: str


class SearchPostResponse(BaseModel):
    id: int
    author: str
    body: str
    time_label: str = Field(serialization_alias="timeLabel")


class SearchResponse(BaseModel):
    users: list[SearchUserResponse]
    rooms: list[SearchRoomResponse]
    posts: list[SearchPostResponse]


class ProfileResponse(BaseModel):
    """个人中心需要的真实统计和资料。"""

    id: int
    username: str
    display_name: str = Field(serialization_alias="displayName")
    following_count: int = Field(serialization_alias="followingCount")
    follower_count: int = Field(serialization_alias="followerCount")
    liked_count: int = Field(serialization_alias="likedCount")


class UpdateProfileRequest(BaseModel):
    """允许修改的个人资料字段；用户名和权限字段不允许客户端覆盖。"""

    display_name: str = Field(min_length=1, max_length=100, alias="displayName")


class MessageSendRequest(BaseModel):
    """发送私信请求。"""

    model_config = ConfigDict(populate_by_name=True)

    recipient_id: int = Field(ge=1)
    body: str = Field(default="", max_length=2000)
    file_ids: list[int] = Field(default_factory=list, max_length=9)


def format_time_label(value: datetime) -> str:
    """把数据库 UTC 时间转成简单的中文相对时间标签。"""
    now = datetime.now(timezone.utc)
    source = (
        value.replace(tzinfo=timezone.utc)
        if value.tzinfo is None
        else value.astimezone(timezone.utc)
    )
    seconds = max(0, int((now - source).total_seconds()))
    if seconds < 60:
        return "刚刚"
    if seconds < 3600:
        return f"{seconds // 60} 分钟前"
    if seconds < 86400:
        return f"{seconds // 3600} 小时前"
    return f"{seconds // 86400} 天前"
