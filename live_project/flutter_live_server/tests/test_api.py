from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.api.deps import get_live_room_service
from app.core.exceptions import NotFoundException
from app.main import app
from app.models.live_room import LiveRoom


class FakeLiveRoomService:
    room = LiveRoom(
        id=1,
        title="测试直播",
        anchor_name="主播",
        anchor_avatar="",
        online_count=10,
        cover_url="",
        status="living",
        play_url="",
        category="技术",
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        updated_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )

    def get_living_rooms(self) -> list[LiveRoom]:
        return [self.room]

    def get_room_detail(self, room_id: int) -> LiveRoom:
        if room_id != self.room.id:
            raise NotFoundException(message="直播间不存在", code=40401)
        return self.room


def test_live_api_response_and_not_found() -> None:
    app.dependency_overrides[get_live_room_service] = FakeLiveRoomService
    try:
        with TestClient(app) as client:
            rooms_response = client.get("/api/v1/live/rooms")
            not_found_response = client.get("/api/v1/live/rooms/999")
    finally:
        app.dependency_overrides.clear()

    assert rooms_response.status_code == 200
    assert rooms_response.json()["data"][0]["anchorName"] == "主播"
    assert not_found_response.status_code == 404
    assert not_found_response.json() == {
        "code": 40401,
        "message": "直播间不存在",
        "data": None,
    }
