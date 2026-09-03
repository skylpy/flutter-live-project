from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class LiveRoomResponse(BaseModel):
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
