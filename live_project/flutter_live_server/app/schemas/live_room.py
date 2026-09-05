from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CreateLiveRoomRequest(BaseModel):
    """主播点击“开始直播”前提交的房间信息。

    这一阶段先不强制登录，便于在两台真机上快速验证推流链路；正式环境应在
    endpoint 上增加当前用户依赖，并用登录用户覆盖 anchor_name。
    """

    model_config = ConfigDict(populate_by_name=True)

    title: str = Field(min_length=1, max_length=255)
    anchor_name: str = Field(
        min_length=1,
        max_length=100,
        alias="anchorName",
    )
    category: str = Field(default="综合", max_length=100)


class LiveRoomResponse(BaseModel):
    """数据库 LiveRoom 对外暴露的安全响应格式。

    serialization_alias 把 Python/数据库字段转换成 Flutter 更习惯的 camelCase。
    """

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    title: str
    anchor_name: str = Field(serialization_alias="anchorName")
    anchor_avatar: str = Field(serialization_alias="anchorAvatar")
    online_count: int = Field(serialization_alias="onlineCount")
    cover_url: str = Field(serialization_alias="coverUrl")
    status: str
    play_url: str = Field(serialization_alias="playUrl")
    category: str
    created_at: datetime = Field(serialization_alias="createdAt")
    updated_at: datetime = Field(serialization_alias="updatedAt")


class LiveRoomHostResponse(LiveRoomResponse):
    """只给主播控制面返回的房间响应。

    pushUrl 是写入 SRS 的凭证式地址，不能出现在观众列表和详情接口中。
    """

    push_url: str = Field(serialization_alias="pushUrl")
    stream_name: str = Field(serialization_alias="streamName")

    @field_validator("push_url", "stream_name", mode="before")
    @classmethod
    def empty_stream_fields_are_safe(cls, value: object) -> str:
        """兼容迁移前的旧 ORM 对象或历史数据中的 NULL。"""
        return value if isinstance(value, str) else ""
