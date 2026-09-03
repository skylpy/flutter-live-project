from datetime import datetime, timezone

from app.models.live_room import LiveRoom
from app.schemas.live_room import LiveRoomResponse


def test_live_room_response_uses_flutter_camel_case() -> None:
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

    payload = LiveRoomResponse.model_validate(room).model_dump(by_alias=True)

    assert payload["anchorName"] == "主播"
    assert payload["onlineCount"] == 10
