"""虚拟居民和直播公屏历史的数据访问。"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.models.ai import LiveChatMessage, VirtualResidentProfile
from app.models.live_room import LiveRoom
from app.models.user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class AiRoomRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def room_is_living(self, room_id: int) -> bool:
        return bool(
            self.db.scalar(
                select(LiveRoom.id).where(LiveRoom.id == room_id, LiveRoom.status == "living")
            )
        )

    def enabled_residents(self) -> list[tuple[User, VirtualResidentProfile]]:
        return self.db.execute(
            select(User, VirtualResidentProfile)
            .join(VirtualResidentProfile, VirtualResidentProfile.user_id == User.id)
            .where(
                User.is_active.is_(True),
                User.is_virtual.is_(True),
                VirtualResidentProfile.is_enabled.is_(True),
            )
            .order_by(User.id.asc())
        ).all()

    def recent_messages(self, room_id: int, limit: int) -> list[tuple]:
        """按时间正序返回有限的公开上下文，避免把整间房的历史送进模型。"""
        rows = self.db.execute(
            select(LiveChatMessage, User, VirtualResidentProfile.role)
            .join(User, User.id == LiveChatMessage.user_id)
            .outerjoin(VirtualResidentProfile, VirtualResidentProfile.user_id == User.id)
            .where(LiveChatMessage.room_id == room_id)
            .order_by(desc(LiveChatMessage.created_at), desc(LiveChatMessage.id))
            .limit(limit)
        ).all()
        return list(reversed(rows))

    def add_message(
        self,
        *,
        room_id: int,
        user: User,
        body: str,
    ) -> LiveChatMessage:
        message = LiveChatMessage(
            room_id=room_id,
            user_id=user.id,
            body=body,
            is_virtual=user.is_virtual,
            created_at=_utcnow(),
        )
        self.db.add(message)
        self.db.commit()
        self.db.refresh(message)
        return message

    def add_virtual_message(
        self,
        *,
        room_id: int,
        resident: User,
        body: str,
    ) -> LiveChatMessage:
        return self.add_message(room_id=room_id, user=resident, body=body)
