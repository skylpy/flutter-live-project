from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


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
