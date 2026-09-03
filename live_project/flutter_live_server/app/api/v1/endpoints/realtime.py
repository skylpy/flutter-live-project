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
    if not token:
        return None, None
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        return int(payload["sub"]), str(payload["username"])
    except (KeyError, TypeError, ValueError, jwt.InvalidTokenError):
        return None, None
