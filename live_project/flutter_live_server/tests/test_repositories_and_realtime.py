from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

from redis.exceptions import RedisError
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.models.base import Base
from app.models.live_room import LiveRoom
from app.models.user import User
from app.repositories.live_room_repository import LiveRoomRepository
from app.services import realtime_service
from app.services.realtime_service import RoomRealtimeHub, UserRealtimeHub, event_time


def test_repositories_filter_living_rooms_and_order_newest_first() -> None:
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine, tables=[User.__table__, LiveRoom.__table__])
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    with Session(engine) as db:
        older = LiveRoom(
            id=1,
            title="旧直播",
            anchor_name="A",
            status="living",
            created_at=now - timedelta(minutes=2),
            updated_at=now,
            anchor_avatar="",
            cover_url="",
            play_url="",
            push_url="",
            stream_name="",
            category="",
        )
        newer = LiveRoom(
            id=2,
            title="新直播",
            anchor_name="B",
            status="living",
            created_at=now,
            updated_at=now,
            anchor_avatar="",
            cover_url="",
            play_url="",
            push_url="",
            stream_name="",
            category="",
        )
        ended = LiveRoom(
            id=3,
            title="已结束",
            anchor_name="C",
            status="ended",
            created_at=now + timedelta(minutes=1),
            updated_at=now,
            anchor_avatar="",
            cover_url="",
            play_url="",
            push_url="",
            stream_name="",
            category="",
        )
        db.add_all([older, newer, ended])
        db.commit()
        repository = LiveRoomRepository(db)
        assert [room.id for room in repository.get_living_rooms()] == [2, 1]
        assert repository.exists(2) is True
        assert repository.get_by_id(999) is None
    engine.dispose()


class FakeWebSocket:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.sent: list[dict] = []

    async def send_json(self, payload: dict) -> None:
        if self.fail:
            raise RuntimeError("closed")
        self.sent.append(payload)


def test_realtime_hubs_fall_back_to_local_broadcast_when_redis_fails(monkeypatch) -> None:
    async def scenario() -> None:
        redis = AsyncMock()
        redis.publish.side_effect = RedisError("redis unavailable")
        monkeypatch.setattr(realtime_service, "get_async_redis", lambda: redis)

        room_hub = RoomRealtimeHub()
        room_socket = FakeWebSocket()
        room_hub._connections[3] = {room_socket}
        await room_hub.publish(3, {"type": "chat", "message": "hello"})
        assert room_socket.sent == [{"type": "chat", "message": "hello"}]

        user_hub = UserRealtimeHub()
        user_socket = FakeWebSocket()
        user_hub._connections[8] = {user_socket}
        await user_hub.publish(8, {"type": "notification", "event": "read_all"})
        assert user_socket.sent == [{"type": "notification", "event": "read_all"}]

        closed = FakeWebSocket(fail=True)
        room_hub._connections[3].add(closed)
        await room_hub.broadcast_local(3, {"type": "system"})
        assert closed not in room_hub._connections[3]

    asyncio.run(scenario())


def test_realtime_disconnect_cleans_connections_and_subscription_errors(monkeypatch) -> None:
    async def scenario() -> None:
        hub = RoomRealtimeHub()
        websocket = FakeWebSocket()
        hub._connections[4] = {websocket}
        await hub.disconnect(4, websocket, None)
        assert 4 not in hub._connections

        class BrokenPubSub:
            async def unsubscribe(self, channel: str) -> None:
                raise RedisError("gone")

            async def close(self) -> None:
                raise RedisError("gone")

        hub._connections[4] = {websocket}
        await hub.disconnect(4, websocket, BrokenPubSub())
        assert 4 not in hub._connections

    asyncio.run(scenario())
    assert event_time(datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc)).endswith("+00:00")
