import asyncio
import json
from typing import Optional

import jwt
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.exceptions import AppException
from app.repositories.ai_room_repository import AiRoomRepository
from app.services.ai_room_service import LiveChatHistoryService, room_bot_director
from app.services.realtime_service import event_time, room_realtime_hub, user_realtime_hub

router = APIRouter(tags=["realtime"])


@router.websocket("/ws/notifications")
async def notification_websocket(
    websocket: WebSocket,
    token: Optional[str] = Query(default=None),
) -> None:
    """登录用户的通知流；消息中心仍保留 HTTP 作为历史数据源。"""
    user_id, username = _user_from_token(token)
    if user_id is None or username is None:
        await websocket.close(code=1008, reason="unauthorized")
        return

    pubsub = await user_realtime_hub.connect(user_id, websocket)
    relay_task = (
        asyncio.create_task(user_realtime_hub.relay(websocket, pubsub))
        if pubsub is not None
        else None
    )
    try:
        await websocket.send_json(
            {
                "type": "system",
                "event": "connected",
                "userId": user_id,
                "userName": username,
                "sentAt": event_time(),
            }
        )
        while True:
            # 用户通知通道只下行；客户端发送内容统一拒绝，避免误把它当成私信写入。
            await websocket.receive_text()
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if relay_task is not None:
            relay_task.cancel()
        await user_realtime_hub.disconnect(user_id, websocket, pubsub)


@router.websocket("/live/ws/rooms/{room_id}")
async def room_websocket(
    websocket: WebSocket,
    room_id: int,
    token: Optional[str] = Query(default=None),
) -> None:
    """一个直播间的弹幕 WebSocket 入口。

    视频不经过此连接；该连接只负责用户认证、聊天消息、在线人数和 Redis 广播。
    """
    user_id, username = _user_from_token(token)
    if user_id is None or username is None:
        await websocket.close(code=1008, reason="unauthorized")
        return

    pubsub = await room_realtime_hub.connect(room_id, websocket)
    online_count = await room_realtime_hub.presence.join(room_id, user_id)
    relay_task = (
        asyncio.create_task(room_realtime_hub.relay(websocket, pubsub))
        if pubsub is not None
        else None
    )
    await room_realtime_hub.publish(
        room_id,
        {
            "type": "presence",
            "event": "joined",
            "roomId": room_id,
            "userName": username,
            "message": f"{username}进入直播间",
            "onlineCount": online_count,
            "sentAt": event_time(),
        },
    )
    # 进房欢迎只是一种低频氛围事件；它在后台运行且不阻塞 WebSocket 建连。
    asyncio.create_task(room_bot_director.on_human_join(room_id=room_id, user_name=username))
    try:
        while True:
            # 客户端每条消息都重新解析和校验，不能信任客户端传来的用户名或房间号。
            raw_message = await websocket.receive_text()
            payload = json.loads(raw_message)
            if payload.get("type") != "chat":
                await websocket.send_json({"type": "error", "message": "不支持的消息类型"})
                continue
            message = str(payload.get("message", "")).strip()
            if not message or len(message) > 200:
                await websocket.send_json({"type": "error", "message": "弹幕长度需为 1-200 个字符"})
                continue
            try:
                with SessionLocal() as db:
                    saved = LiveChatHistoryService(AiRoomRepository(db)).save_human_message(
                        room_id=room_id,
                        user_id=user_id,
                        body=message,
                    )
            except AppException as exc:
                await websocket.send_json({"type": "error", "message": exc.message})
                continue
            except SQLAlchemyError:
                # 历史写入失败时不能把临时消息伪装成已送达；提示客户端重试。
                await websocket.send_json({"type": "error", "message": "弹幕发送失败，请稍后重试"})
                continue
            await room_realtime_hub.publish(
                room_id,
                {
                    "type": "chat",
                    "roomId": room_id,
                    "id": saved.id,
                    "userId": user_id,
                    "userName": username,
                    "message": message,
                    "isVirtual": False,
                    "sentAt": event_time(saved.created_at),
                },
            )
            asyncio.create_task(
                room_bot_director.on_human_chat(
                    room_id=room_id,
                    user_name=username,
                    message=message,
                )
            )
    except (WebSocketDisconnect, json.JSONDecodeError):
        pass
    finally:
        # 无论客户端正常关闭还是异常断开，都要撤销在线人数并广播离开事件。
        if relay_task is not None:
            relay_task.cancel()
        online_count = await room_realtime_hub.presence.leave(room_id, user_id)
        await room_realtime_hub.disconnect(room_id, websocket, pubsub)
        await room_realtime_hub.publish(
            room_id,
            {
                "type": "presence",
                "event": "left",
                "roomId": room_id,
                "userName": username,
                "message": f"{username}离开直播间",
                "onlineCount": online_count,
                "sentAt": event_time(),
            },
        )


def _user_from_token(token: Optional[str]) -> tuple[Optional[int], Optional[str]]:
    """从 WebSocket 查询参数解析用户身份；失败时返回两个 None。"""
    if not token:
        return None, None
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        return int(payload["sub"]), str(payload["username"])
    except (KeyError, TypeError, ValueError, jwt.InvalidTokenError):
        return None, None
