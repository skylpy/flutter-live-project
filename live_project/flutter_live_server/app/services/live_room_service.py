from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from app.core.config import settings
from app.core.exceptions import AppException, NotFoundException
from app.models.live_room import LiveRoom
from app.repositories.live_room_repository import LiveRoomRepository
from app.schemas.live_room import CreateLiveRoomRequest
from app.services.media_server_client import MediaServerClient


class LiveRoomService:
    """直播间业务层。

    Service 负责把“找不到房间”转换为业务异常，Repository 只返回 None。
    """

    def __init__(
        self,
        repository: LiveRoomRepository,
        media_server: MediaServerClient | None = None,
    ) -> None:
        self.repository = repository
        self.media_server = media_server or MediaServerClient()

    def get_living_rooms(self) -> list[LiveRoom]:
        """获取首页需要的正在直播房间，并与媒体服务器做状态对账。

        数据库是房间控制面的最终记录，但 RTMP 推流可能因 App 被杀、网络
        断开或进程重启而没有机会调用 stop 接口。SRS 明确返回活动流集合时，
        把已经没有 publish.active 的动态房间收敛为 ended；探针不可用时不做
        猜测，继续返回数据库结果，避免媒体控制 API 短暂故障造成误清理。
        """
        rooms = self.repository.get_living_rooms()
        active_stream_names = self.media_server.active_stream_names()
        if active_stream_names is None:
            return rooms

        visible_rooms: list[LiveRoom] = []
        for room in rooms:
            # 历史演示房间可能没有 stream_name，它们使用固定 HLS 地址，
            # 不能拿它们去和 SRS 的动态 RTMP 流集合比较。
            if room.stream_name and room.stream_name not in active_stream_names:
                room.status = "ended"
                room.online_count = 0
                room.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
                self.repository.save(room)
                continue
            visible_rooms.append(room)
        return visible_rooms

    def get_room_detail(self, room_id: int) -> LiveRoom:
        """获取详情并把不存在情况转换成统一 404。"""
        room = self.repository.get_by_id(room_id)
        if room is None:
            raise NotFoundException(message="直播间不存在", code=40401)
        return room

    def create_room(
        self,
        payload: CreateLiveRoomRequest,
        *,
        owner_id: int,
        owner_display_name: str,
    ) -> LiveRoom:
        """创建一个尚未推流的房间，并生成一组不可预测的流地址。

        stream_name 是服务端生成的随机值。主播拿到 push_url 后推 RTMP，SRS
        会把相同 stream_name 转成 play_url；观众随后从 living 列表拿到播放地址。
        """
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        stream_name = f"room_{uuid4().hex[:20]}"
        media_base = f"{settings.media_server_host}:{settings.media_rtmp_port}"
        http_base = f"{settings.media_server_host}:{settings.media_http_port}"
        room = LiveRoom(
            title=payload.title.strip(),
            anchor_user_id=owner_id,
            anchor_name=owner_display_name.strip() or payload.anchor_name.strip(),
            category=payload.category.strip() or "综合",
            status="preparing",
            online_count=0,
            anchor_avatar="",
            cover_url="",
            stream_name=stream_name,
            push_url=f"rtmp://{media_base}/{settings.media_app}/{stream_name}",
            play_url=(f"http://{http_base}/{settings.media_app}/{stream_name}.m3u8"),
            created_at=now,
            updated_at=now,
        )
        return self.repository.add(room)

    def start_room(self, room_id: int, *, owner_id: int) -> LiveRoom:
        """确认 SRS 已收到推流后再切换为 living。

        控制 API 暂时不可用时不直接误判为推流失败；但 SRS 明确可用且在
        有界等待后仍没有 active 流时，拒绝把房间展示给观众。
        """
        room = self._get_room(room_id)
        self._assert_owner(room, owner_id)
        if room.status == "ended":
            raise AppException("直播间已结束，不能重复开播", code=40902, status_code=409)
        if room.status == "living":
            return room
        if room.stream_name:
            media_state = self.media_server.wait_for_active_stream(room.stream_name)
            if media_state is None:
                raise AppException(
                    "媒体服务器暂不可用，不能确认推流状态",
                    code=50303,
                    status_code=503,
                )
            if media_state is False:
                raise AppException("媒体服务器尚未确认推流", code=40903, status_code=409)
        room.status = "living"
        room.online_count = max(room.online_count, 1)
        room.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return self.repository.save(room)

    def stop_room(self, room_id: int, *, owner_id: int) -> LiveRoom:
        """结束直播并从 living 列表移除。"""
        room = self._get_room(room_id)
        self._assert_owner(room, owner_id)
        if room.status == "ended":
            return room
        room.status = "ended"
        room.online_count = 0
        room.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return self.repository.save(room)

    def _get_room(self, room_id: int) -> LiveRoom:
        room = self.repository.get_by_id(room_id)
        if room is None:
            raise NotFoundException(message="直播间不存在", code=40401)
        return room

    @staticmethod
    def _assert_owner(room: LiveRoom, owner_id: int) -> None:
        """只允许创建者控制房间，历史上没有归属人的房间也不放行。"""
        if room.anchor_user_id != owner_id:
            raise AppException("没有权限操作该直播间", code=40301, status_code=403)
