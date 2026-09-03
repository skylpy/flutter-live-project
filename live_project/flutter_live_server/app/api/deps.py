from fastapi import Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.repositories.live_room_repository import LiveRoomRepository
from app.services.live_room_service import LiveRoomService


def get_live_room_service(db: Session = Depends(get_db)) -> LiveRoomService:
    return LiveRoomService(LiveRoomRepository(db))
