from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


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

    recipient_id: int = Field(alias="recipientId", ge=1)
    body: str = Field(min_length=1, max_length=2000)


def format_time_label(value: datetime) -> str:
    """把数据库 UTC 时间转成简单的中文相对时间标签。"""
    now = datetime.utcnow()
    seconds = max(0, int((now - value).total_seconds()))
    if seconds < 60:
        return "刚刚"
    if seconds < 3600:
        return f"{seconds // 60} 分钟前"
    if seconds < 86400:
        return f"{seconds // 3600} 小时前"
    return f"{seconds // 86400} 天前"
