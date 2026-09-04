from fastapi import APIRouter, Depends, Path

from app.api.deps import get_live_room_service
from app.schemas.common import ApiResponse, success
from app.schemas.live_room import LiveRoomResponse
from app.services.live_room_service import LiveRoomService

router = APIRouter(prefix="/live", tags=["live"])


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
) -> ApiResponse[LiveRoomResponse]:
    """返回一个直播间详情；不存在时由 Service 抛出统一 404 异常。"""
    return success(service.get_room_detail(room_id))
