from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.api.deps import get_current_user, get_live_room_service
from app.api.deps_social import get_social_service
from app.main import app
from app.models.live_room import LiveRoom
from app.services.realtime_service import room_realtime_hub


class FakeSocialService:
    def room_interaction_state(self, room_id: int, user_id: int | None) -> dict[str, bool | int]:
        return {"following": user_id == 7, "liked": False, "like_count": 0}


class FakeLiveRoomService:
    def __init__(self) -> None:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        self.room = LiveRoom(
            id=7,
            title="主播测试间",
            anchor_user_id=7,
            anchor_name="真实主播",
            anchor_avatar="",
            cover_url="",
            online_count=0,
            status="preparing",
            play_url="https://cdn.example.invalid/live/7.m3u8",
            push_url="rtmp://secret.example.invalid/live/7",
            stream_name="room_7",
            category="技术",
            created_at=now,
            updated_at=now,
        )

    def create_room(self, payload, *, owner_id: int, owner_display_name: str) -> LiveRoom:
        self.room.anchor_user_id = owner_id
        self.room.anchor_name = owner_display_name
        return self.room

    def get_room_detail(self, room_id: int) -> LiveRoom:
        return self.room

    def get_living_rooms(self) -> list[LiveRoom]:
        return [self.room] if self.room.status == "living" else []

    def start_room(self, room_id: int, *, owner_id: int) -> LiveRoom:
        self.room.status = "living"
        self.room.online_count = 1
        return self.room

    def stop_room(self, room_id: int, *, owner_id: int) -> LiveRoom:
        self.room.status = "ended"
        self.room.online_count = 0
        return self.room


def test_live_api_separates_host_push_credentials_from_viewer_payloads() -> None:
    service = FakeLiveRoomService()
    app.dependency_overrides[get_live_room_service] = lambda: service
    app.dependency_overrides[get_social_service] = FakeSocialService
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=7, display_name="真实主播"
    )
    publish = AsyncMock()
    original_publish = room_realtime_hub.publish
    room_realtime_hub.publish = publish
    try:
        with TestClient(app) as client:
            created = client.post(
                "/api/v1/live/rooms",
                json={"title": "客户端标题", "anchorName": "伪造名称", "category": "技术"},
            )
            started = client.post("/api/v1/live/rooms/7/start")
            viewer_list = client.get("/api/v1/live/rooms")
            viewer_detail = client.get("/api/v1/live/rooms/7")
            stopped = client.post("/api/v1/live/rooms/7/stop")
    finally:
        room_realtime_hub.publish = original_publish
        app.dependency_overrides.clear()

    assert created.status_code == 200
    assert created.json()["data"]["pushUrl"].startswith("rtmp://")
    assert started.json()["data"]["pushUrl"].startswith("rtmp://")
    assert "pushUrl" not in viewer_list.json()["data"][0]
    assert "pushUrl" not in viewer_detail.json()["data"]
    assert stopped.json()["data"]["status"] == "ended"
    publish.assert_awaited_once()


def test_live_api_rejects_invalid_path_and_body_boundaries() -> None:
    service = FakeLiveRoomService()
    app.dependency_overrides[get_live_room_service] = lambda: service
    app.dependency_overrides[get_social_service] = FakeSocialService
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=7, display_name="真实主播"
    )
    try:
        with TestClient(app) as client:
            invalid_room = client.get("/api/v1/live/rooms/0")
            invalid_create = client.post(
                "/api/v1/live/rooms", json={"title": "", "anchorName": "主播"}
            )
    finally:
        app.dependency_overrides.clear()

    assert invalid_room.status_code == 422
    assert invalid_create.status_code == 422
    assert invalid_room.json() == {
        "code": 42200,
        "message": "请求数据校验失败",
        "data": None,
    }
