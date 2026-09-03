import asyncio
import json
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import WebSocket
from redis.asyncio.client import PubSub
from redis.exceptions import RedisError

from app.core.redis import get_async_redis


class PresenceService:
    def _key(self, room_id: int) -> str:
        return f"live:room:{room_id}:online_users"

    async def join(self, room_id: int, user_id: int) -> Optional[int]:
        try:
            redis = get_async_redis()
            key = self._key(room_id)
            await redis.sadd(key, user_id)
            await redis.expire(key, 3600)
            return int(await redis.scard(key))
        except RedisError:
            return None

    async def leave(self, room_id: int, user_id: int) -> Optional[int]:
        try:
            redis = get_async_redis()
            key = self._key(room_id)
            await redis.srem(key, user_id)
            return int(await redis.scard(key))
        except RedisError:
            return None


class RoomRealtimeHub:
    def __init__(self) -> None:
        self.presence = PresenceService()
        self._connections: dict[int, set[WebSocket]] = {}

    async def connect(self, room_id: int, websocket: WebSocket) -> Optional[PubSub]:
        await websocket.accept()
        self._connections.setdefault(room_id, set()).add(websocket)
        try:
            pubsub = get_async_redis().pubsub()
            await pubsub.subscribe(self._channel(room_id))
            return pubsub
        except RedisError:
            return None

    async def disconnect(
        self,
        room_id: int,
        websocket: WebSocket,
        pubsub: Optional[PubSub],
    ) -> None:
        self._connections.get(room_id, set()).discard(websocket)
        if not self._connections.get(room_id):
            self._connections.pop(room_id, None)
        if pubsub is not None:
            try:
                await pubsub.unsubscribe(self._channel(room_id))
                await pubsub.close()
            except RedisError:
                pass

    async def publish(self, room_id: int, payload: dict[str, Any]) -> None:
        message = json.dumps(payload, ensure_ascii=False)
        try:
            await get_async_redis().publish(self._channel(room_id), message)
        except RedisError:
            await self.broadcast_local(room_id, payload)

    async def relay(self, websocket: WebSocket, pubsub: PubSub) -> None:
        try:
            while True:
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True,
                    timeout=1.0,
                )
                if message is not None and isinstance(message.get("data"), str):
                    await websocket.send_text(message["data"])
                await asyncio.sleep(0)
        except (RedisError, RuntimeError):
            return

    async def broadcast_local(self, room_id: int, payload: dict[str, Any]) -> None:
        for websocket in tuple(self._connections.get(room_id, ())):
            try:
                await websocket.send_json(payload)
            except RuntimeError:
                self._connections.get(room_id, set()).discard(websocket)

    @staticmethod
    def _channel(room_id: int) -> str:
        return f"live:room:{room_id}:chat"


room_realtime_hub = RoomRealtimeHub()


def event_time() -> str:
    return datetime.now(timezone.utc).isoformat()
