from datetime import datetime, timezone

from app.models.live_room import LiveRoom
from app.schemas.live_room import LiveRoomResponse
from app.schemas.social import SearchResponse


def test_live_room_response_uses_flutter_camel_case() -> None:
    """确保后端字段能序列化成 Flutter 模型使用的命名。"""
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


def test_phase4_search_response_uses_flutter_camel_case() -> None:
    payload = SearchResponse(
        users=[{"id": 1, "username": "kevin", "display_name": "Kevin"}],
        rooms=[
            {
                "id": 2,
                "title": "测试直播",
                "anchor_name": "Kevin",
                "online_count": 12,
                "status": "living",
                "category": "技术",
            }
        ],
        posts=[
            {"id": 3, "author": "Kevin", "body": "测试动态", "time_label": "刚刚"}
        ],
    ).model_dump(by_alias=True)

    assert payload["users"][0]["displayName"] == "Kevin"
    assert payload["rooms"][0]["anchorName"] == "Kevin"
    assert payload["rooms"][0]["onlineCount"] == 12
    assert payload["posts"][0]["timeLabel"] == "刚刚"
