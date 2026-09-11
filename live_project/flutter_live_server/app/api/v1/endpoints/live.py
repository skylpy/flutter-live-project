from typing import Optional

from fastapi import APIRouter, Depends, Path, Query

from app.api.deps import (
    get_current_user,
    get_live_chat_history_service,
    get_live_room_service,
    get_optional_current_user,
)
from app.api.deps_social import get_social_service
from app.models.user import User
from app.schemas.ai import LiveChatHistoryResponse
from app.schemas.common import ApiResponse, success
from app.schemas.live_room import (
    CreateLiveRoomRequest,
    LiveRoomHostResponse,
    LiveRoomResponse,
)
from app.services.ai_room_service import LiveChatHistoryService
from app.services.live_room_service import LiveRoomService
from app.services.realtime_service import event_time, room_realtime_hub
from app.services.social_service import SocialService

router = APIRouter(prefix="/live", tags=["live"])


@router.post("/rooms", response_model=ApiResponse[LiveRoomHostResponse])
def create_live_room(
    payload: CreateLiveRoomRequest,
    service: LiveRoomService = Depends(get_live_room_service),
    user: User = Depends(get_current_user),
) -> ApiResponse[LiveRoomHostResponse]:
    """创建房间并返回主播端 pushUrl 与观众端 playUrl。"""
    return success(
        service.create_room(
            payload,
            owner_id=user.id,
            owner_display_name=user.display_name,
        ),
        message="直播间已创建",
    )


@router.get("/rooms", response_model=ApiResponse[list[LiveRoomResponse]])
def get_live_rooms(
    service: LiveRoomService = Depends(get_live_room_service),
) -> ApiResponse[list[LiveRoomResponse]]:
    """返回当前 status=living 的直播间列表。"""
    return success(service.get_living_rooms())


@router.get("/rooms/{room_id}", response_model=ApiResponse[LiveRoomResponse])
def get_live_room_detail(
    room_id: int = Path(..., ge=1),
    service: LiveRoomService = Depends(get_live_room_service),
    social_service: SocialService = Depends(get_social_service),
    user: Optional[User] = Depends(get_optional_current_user),
) -> ApiResponse[LiveRoomResponse]:
    """返回详情和当前用户的互动快照；游客仍可观看。"""
    room = service.get_room_detail(room_id)
    response = LiveRoomResponse.model_validate(room).model_copy(
        update=social_service.room_interaction_state(
            room_id,
            user.id if user is not None else None,
        )
    )
    return success(response)


@router.get(
    "/rooms/{room_id}/chat/messages",
    response_model=ApiResponse[list[LiveChatHistoryResponse]],
)
def get_live_chat_history(
    room_id: int = Path(..., ge=1),
    limit: int = Query(default=60, ge=1, le=120),
    service: LiveChatHistoryService = Depends(get_live_chat_history_service),
    _: User = Depends(get_current_user),
) -> ApiResponse[list[LiveChatHistoryResponse]]:
    """用户重新进入同一房间时回填公开弹幕；只返回有限最近记录。"""
    return success(service.list_history(room_id, limit=limit))


@router.post("/rooms/{room_id}/start", response_model=ApiResponse[LiveRoomHostResponse])
def start_live_room(
    room_id: int = Path(..., ge=1),
    service: LiveRoomService = Depends(get_live_room_service),
    user: User = Depends(get_current_user),
) -> ApiResponse[LiveRoomHostResponse]:
    """主播端在 RTMP 连接成功后调用，使房间出现在观众列表。"""
    return success(service.start_room(room_id, owner_id=user.id), message="直播已开始")


@router.post("/rooms/{room_id}/stop", response_model=ApiResponse[LiveRoomHostResponse])
async def stop_live_room(
    room_id: int = Path(..., ge=1),
    service: LiveRoomService = Depends(get_live_room_service),
    user: User = Depends(get_current_user),
) -> ApiResponse[LiveRoomHostResponse]:
    """主播端停止推流后调用，使房间从观众列表消失。"""
    current_room = service.get_room_detail(room_id)
    was_living = current_room.status == "living"
    room = service.stop_room(room_id, owner_id=user.id)
    if was_living:
        await room_realtime_hub.publish(
            room_id,
            {
                "type": "system",
                "event": "room_ended",
                "roomId": room_id,
                "userName": room.anchor_name,
                "message": "主播已结束直播，直播间即将关闭",
                "onlineCount": 0,
                "sentAt": event_time(),
            },
        )
    return success(room, message="直播已结束")
