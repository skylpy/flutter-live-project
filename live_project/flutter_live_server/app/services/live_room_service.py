from app.core.exceptions import NotFoundException
from app.models.live_room import LiveRoom
from app.repositories.live_room_repository import LiveRoomRepository


class LiveRoomService:
    def __init__(self, repository: LiveRoomRepository) -> None:
        self.repository = repository

    def get_living_rooms(self) -> list[LiveRoom]:
        return self.repository.get_living_rooms()

    def get_room_detail(self, room_id: int) -> LiveRoom:
        room = self.repository.get_by_id(room_id)
        if room is None:
            raise NotFoundException(message="直播间不存在", code=40401)
        return room
