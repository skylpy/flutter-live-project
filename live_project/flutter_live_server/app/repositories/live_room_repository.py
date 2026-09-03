from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.live_room import LiveRoom


class LiveRoomRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_living_rooms(self) -> list[LiveRoom]:
        statement = (
            select(LiveRoom)
            .where(LiveRoom.status == "living")
            .order_by(LiveRoom.created_at.desc())
        )
        return list(self.db.scalars(statement).all())

    def get_by_id(self, room_id: int) -> Optional[LiveRoom]:
        return self.db.get(LiveRoom, room_id)

    def exists(self, room_id: int) -> bool:
        return self.get_by_id(room_id) is not None
