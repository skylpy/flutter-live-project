from __future__ import annotations

from fastapi import APIRouter, Depends, Path, Query

from app.api.deps import get_current_user, get_live_room_service
from app.api.deps_social import get_social_service
from app.models.user import User
from app.schemas.common import ApiResponse, success
from app.schemas.social import (
    FeedPostResponse,
    FollowedUserResponse,
    MessageConversationResponse,
    MessageSendRequest,
    NotificationResponse,
    ProfileResponse,
    SearchResponse,
    ToggleInteractionResponse,
    UpdateProfileRequest,
)
from app.services.live_room_service import LiveRoomService
from app.services.realtime_service import event_time, user_realtime_hub
from app.services.social_service import SocialService

router = APIRouter(tags=["phase4"])


@router.get("/search", response_model=ApiResponse[SearchResponse])
def search(
    q: str = Query(..., min_length=1, max_length=100),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[SearchResponse]:
    """搜索用户、正在直播的房间和动态正文。"""
    return success(service.search(q.strip()))


@router.get("/feed/posts", response_model=ApiResponse[list[FeedPostResponse]])
def list_feed_posts(
    tab: str = Query(default="推荐", max_length=10),
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[list[FeedPostResponse]]:
    """返回真实动态列表；关注 Tab 只返回当前用户关注作者的动态。"""
    return success(service.list_posts(tab, user))


@router.post("/feed/posts/{post_id}/like", response_model=ApiResponse[ToggleInteractionResponse])
def toggle_feed_like(
    post_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[ToggleInteractionResponse]:
    """幂等切换动态点赞，返回最新计数供客户端更新单项状态。"""
    return success(service.toggle_feed_like(post_id, user))


@router.get("/profile/me", response_model=ApiResponse[ProfileResponse])
def get_profile(
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[ProfileResponse]:
    """返回个人资料和统计数据。"""
    return success(service.profile(user))


@router.put("/profile/me", response_model=ApiResponse[ProfileResponse])
def update_profile(
    payload: UpdateProfileRequest,
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[ProfileResponse]:
    """只修改允许用户编辑的展示名。"""
    return success(service.update_profile(user, payload.display_name))


@router.get("/messages/conversations", response_model=ApiResponse[list[MessageConversationResponse]])
def list_conversations(
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[list[MessageConversationResponse]]:
    """返回消息中心会话摘要。"""
    return success(service.conversations(user))


@router.post("/messages", response_model=ApiResponse[dict], status_code=201)
async def send_message(
    payload: MessageSendRequest,
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[dict]:
    """发送一条私信；具体会话列表通过 GET 重新读取，避免本地状态漂移。"""
    result = service.send_message(payload, user)
    await user_realtime_hub.publish(
        payload.recipient_id,
        {
            "type": "notification",
            "event": "message",
            "notification": {
                "id": f"message:{result['id']}",
                "type": "互动消息",
                "title": user.display_name,
                "body": str(result["body"]),
                "timeLabel": "刚刚",
                "unread": True,
            },
            "sentAt": event_time(),
        },
    )
    return success(result, message="消息已发送")


@router.post("/messages/conversations/{other_user_id}/read", response_model=ApiResponse[None])
def mark_conversation_read(
    other_user_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[None]:
    service.mark_conversation_read(user, other_user_id)
    return success(None, message="会话已读")


@router.get("/notifications", response_model=ApiResponse[list[NotificationResponse]])
def list_notifications(
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[list[NotificationResponse]]:
    return success(service.notifications(user))


@router.post("/notifications/read", response_model=ApiResponse[None])
async def mark_notifications_read(
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[None]:
    service.mark_notifications_read(user)
    await user_realtime_hub.publish(
        user.id,
        {
            "type": "notification",
            "event": "read_all",
            "sentAt": event_time(),
        },
    )
    return success(None, message="通知已读")


@router.get("/following", response_model=ApiResponse[list[FollowedUserResponse]])
def list_following(
    user: User = Depends(get_current_user),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[list[FollowedUserResponse]]:
    return success(service.following(user))


@router.post("/live/rooms/{room_id}/follow", response_model=ApiResponse[ToggleInteractionResponse])
async def toggle_room_follow(
    room_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    live_service: LiveRoomService = Depends(get_live_room_service),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[ToggleInteractionResponse]:
    """切换直播间关注；目标房间不存在时沿用直播业务的统一 404。"""
    room = live_service.get_room_detail(room_id)
    result = service.toggle_room_follow(room, user)
    if result.active and room.anchor_user_id and room.anchor_user_id != user.id:
        await user_realtime_hub.publish(
            room.anchor_user_id,
            {
                "type": "notification",
                "event": "room_followed",
                "notification": {
                    "id": f"room-follow:{room.id}:{user.id}",
                    "type": "新关注",
                    "title": user.display_name,
                    "body": f"关注了你的直播间《{room.title}》",
                    "timeLabel": "刚刚",
                    "unread": True,
                },
                "sentAt": event_time(),
            },
        )
    return success(result)


@router.post("/live/rooms/{room_id}/like", response_model=ApiResponse[ToggleInteractionResponse])
async def toggle_room_like(
    room_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    live_service: LiveRoomService = Depends(get_live_room_service),
    service: SocialService = Depends(get_social_service),
) -> ApiResponse[ToggleInteractionResponse]:
    """切换直播间点赞并返回最新总数。"""
    room = live_service.get_room_detail(room_id)
    result = service.toggle_room_like(room, user)
    if result.active and room.anchor_user_id and room.anchor_user_id != user.id:
        await user_realtime_hub.publish(
            room.anchor_user_id,
            {
                "type": "notification",
                "event": "room_liked",
                "notification": {
                    "id": f"room-like:{room.id}:{user.id}:{result.count}",
                    "type": "直播互动",
                    "title": user.display_name,
                    "body": f"赞了你的直播间《{room.title}》",
                    "timeLabel": "刚刚",
                    "unread": True,
                },
                "sentAt": event_time(),
            },
        )
    return success(result)
