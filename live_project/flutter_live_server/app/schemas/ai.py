from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class LiveChatHistoryResponse(BaseModel):
    """直播间历史弹幕；字段与 WebSocket chat 事件保持一致。"""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    room_id: int = Field(serialization_alias="roomId")
    user_id: int = Field(serialization_alias="userId")
    user_name: str = Field(serialization_alias="userName")
    message: str
    sent_at: datetime = Field(serialization_alias="sentAt")
    is_virtual: bool = Field(serialization_alias="isVirtual")
    virtual_role: Optional[str] = Field(default=None, serialization_alias="virtualRole")
