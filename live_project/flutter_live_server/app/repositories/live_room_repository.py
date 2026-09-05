from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.live_room import LiveRoom


class LiveRoomRepository:
    """直播间数据库访问层。

    Repository 只负责查询，不决定 HTTP 状态码，也不拼装 API 响应。
    """

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_living_rooms(self) -> list[LiveRoom]:
        """按创建时间倒序返回正在直播的房间。"""
        statement = (
            select(LiveRoom).where(LiveRoom.status == "living").order_by(LiveRoom.created_at.desc())
        )
        return list(self.db.scalars(statement).all())

    def get_by_id(self, room_id: int) -> Optional[LiveRoom]:
        """按主键查询房间，查不到时返回 None。"""
        return self.db.get(LiveRoom, room_id)

    def exists(self, room_id: int) -> bool:
        """判断房间是否存在，供未来创建/修改接口复用。"""
        return self.get_by_id(room_id) is not None

    def add(self, room: LiveRoom) -> LiveRoom:
        """新增房间并刷新自增主键。"""
        self.db.add(room)
        # 一个 HTTP 请求对应一个事务；提交后房间才会被下一台手机的请求看见。
        self.db.commit()
        self.db.refresh(room)
        return room

    def save(self, room: LiveRoom) -> LiveRoom:
        """保存已有房间的状态变化。"""
        self.db.add(room)
        self.db.commit()
        self.db.refresh(room)
        return room
