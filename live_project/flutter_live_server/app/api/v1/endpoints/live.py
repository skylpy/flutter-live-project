from fastapi import APIRouter, Depends, Path

from app.api.deps import get_live_room_service
from app.schemas.common import ApiResponse, success
from app.schemas.live_room import (
    CreateLiveRoomRequest,
    LiveRoomHostResponse,
    LiveRoomResponse,
)
from app.services.live_room_service import LiveRoomService

router = APIRouter(prefix="/live", tags=["live"])


@router.post("/rooms", response_model=ApiResponse[LiveRoomHostResponse])
def create_live_room(
    payload: CreateLiveRoomRequest,
    service: LiveRoomService = Depends(get_live_room_service),
) -> ApiResponse[LiveRoomHostResponse]:
    """创建房间并返回主播端 pushUrl 与观众端 playUrl。"""
    return success(service.create_room(payload), message="直播间已创建")


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


@router.post("/rooms/{room_id}/start", response_model=ApiResponse[LiveRoomHostResponse])
def start_live_room(
    room_id: int = Path(..., ge=1),
    service: LiveRoomService = Depends(get_live_room_service),
) -> ApiResponse[LiveRoomHostResponse]:
    """主播端在 RTMP 连接成功后调用，使房间出现在观众列表。"""
    return success(service.start_room(room_id), message="直播已开始")


@router.post("/rooms/{room_id}/stop", response_model=ApiResponse[LiveRoomHostResponse])
def stop_live_room(
    room_id: int = Path(..., ge=1),
    service: LiveRoomService = Depends(get_live_room_service),
) -> ApiResponse[LiveRoomHostResponse]:
    """主播端停止推流后调用，使房间从观众列表消失。"""
    return success(service.stop_room(room_id), message="直播已结束")
