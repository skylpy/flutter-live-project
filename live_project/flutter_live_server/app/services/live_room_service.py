from app.core.exceptions import NotFoundException
from app.models.live_room import LiveRoom
from app.repositories.live_room_repository import LiveRoomRepository


class LiveRoomService:
    """直播间业务层。

    Service 负责把“找不到房间”转换为业务异常，Repository 只返回 None。
    """
    def __init__(self, repository: LiveRoomRepository) -> None:
        self.repository = repository

    def get_living_rooms(self) -> list[LiveRoom]:
        """获取首页需要的正在直播房间。"""
        return self.repository.get_living_rooms()

    def get_room_detail(self, room_id: int) -> LiveRoom:
        """获取详情并把不存在情况转换成统一 404。"""
        room = self.repository.get_by_id(room_id)
        if room is None:
            raise NotFoundException(message="直播间不存在", code=40401)
        return room
