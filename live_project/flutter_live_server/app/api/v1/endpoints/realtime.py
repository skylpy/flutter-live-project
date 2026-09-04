import asyncio
import json
from typing import Optional

import jwt
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from app.core.config import settings
from app.services.realtime_service import event_time, room_realtime_hub

router = APIRouter(tags=["realtime"])


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
            "onlineCount": online_count,
            "sentAt": event_time(),
        },
    )
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
                await websocket.send_json(
                    {"type": "error", "message": "弹幕长度需为 1-200 个字符"}
                )
                continue
            await room_realtime_hub.publish(
                room_id,
                {
                    "type": "chat",
                    "roomId": room_id,
                    "userId": user_id,
                    "userName": username,
                    "message": message,
                    "sentAt": event_time(),
                },
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
