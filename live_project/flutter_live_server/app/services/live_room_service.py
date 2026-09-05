from datetime import datetime, timezone
from uuid import uuid4

from app.core.config import settings
from app.core.exceptions import NotFoundException
from app.models.live_room import LiveRoom
from app.repositories.live_room_repository import LiveRoomRepository
from app.schemas.live_room import CreateLiveRoomRequest


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

    def create_room(self, payload: CreateLiveRoomRequest) -> LiveRoom:
        """创建一个尚未推流的房间，并生成一组不可预测的流地址。

        stream_name 是服务端生成的随机值。主播拿到 push_url 后推 RTMP，SRS
        会把相同 stream_name 转成 play_url；观众随后从 living 列表拿到播放地址。
        """
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        stream_name = f"room_{uuid4().hex[:20]}"
        media_base = (
            f"{settings.media_server_host}:{settings.media_rtmp_port}"
        )
        http_base = (
            f"{settings.media_server_host}:{settings.media_http_port}"
        )
        room = LiveRoom(
            title=payload.title.strip(),
            anchor_name=payload.anchor_name.strip(),
            category=payload.category.strip() or "综合",
            status="preparing",
            online_count=0,
            anchor_avatar="",
            cover_url="",
            stream_name=stream_name,
            push_url=f"rtmp://{media_base}/{settings.media_app}/{stream_name}",
            play_url=(
                f"http://{http_base}/{settings.media_app}/{stream_name}.m3u8"
            ),
            created_at=now,
            updated_at=now,
        )
        return self.repository.add(room)

    def start_room(self, room_id: int) -> LiveRoom:
        """将房间切换为 living，供观众列表立即发现。"""
        room = self._get_room(room_id)
        room.status = "living"
        room.online_count = max(room.online_count, 1)
        room.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return self.repository.save(room)

    def stop_room(self, room_id: int) -> LiveRoom:
        """结束直播并从 living 列表移除。"""
        room = self._get_room(room_id)
        room.status = "ended"
        room.online_count = 0
        room.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return self.repository.save(room)

    def _get_room(self, room_id: int) -> LiveRoom:
        room = self.repository.get_by_id(room_id)
        if room is None:
            raise NotFoundException(message="直播间不存在", code=40401)
        return room
