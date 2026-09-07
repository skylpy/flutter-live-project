from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app.core.exceptions import AppException
from app.models.live_room import LiveRoom
from app.schemas.live_room import CreateLiveRoomRequest
from app.services.live_room_service import LiveRoomService


class FakeRepository:
    def __init__(self) -> None:
        self.rooms: dict[int, LiveRoom] = {}
        self.next_id = 1

    def get_by_id(self, room_id: int) -> LiveRoom | None:
        return self.rooms.get(room_id)

    def get_living_rooms(self) -> list[LiveRoom]:
        return [room for room in self.rooms.values() if room.status == "living"]

    def add(self, room: LiveRoom) -> LiveRoom:
        room.id = self.next_id
        self.next_id += 1
        self.rooms[room.id] = room
        return room

    def save(self, room: LiveRoom) -> LiveRoom:
        self.rooms[room.id] = room
        return room


class FakeMediaServer:
    def __init__(self, state: bool | None) -> None:
        self.state = state

    def wait_for_active_stream(self, stream_name: str) -> bool | None:
        return self.state

    def active_stream_names(self) -> set[str] | None:
        return None


class ReconcilingFakeMediaServer(FakeMediaServer):
    def __init__(self, active_stream_names: set[str] | None) -> None:
        super().__init__(True)
        self._active_stream_names = active_stream_names

    def active_stream_names(self) -> set[str] | None:
        return self._active_stream_names


def test_create_room_binds_authenticated_owner_and_display_name() -> None:
    repository = FakeRepository()
    service = LiveRoomService(repository, FakeMediaServer(True))

    room = service.create_room(
        CreateLiveRoomRequest(title="测试直播", anchorName="客户端伪造", category="技术"),
        owner_id=7,
        owner_display_name="登录用户",
    )

    assert room.anchor_user_id == 7
    assert room.anchor_name == "登录用户"
    assert room.status == "preparing"
    assert room.push_url.startswith("rtmp://")


@pytest.mark.parametrize(
    ("media_state", "expected_code", "expected_status"),
    [(None, 50303, 503), (False, 40903, 409)],
)
def test_start_room_does_not_mark_living_without_media_confirmation(
    media_state: bool | None,
    expected_code: int,
    expected_status: int,
) -> None:
    repository = FakeRepository()
    service = LiveRoomService(repository, FakeMediaServer(media_state))
    room = LiveRoom(
        id=1,
        title="测试直播",
        anchor_user_id=7,
        anchor_name="主播",
        status="preparing",
        stream_name="room_test",
        play_url="http://127.0.0.1/live/room_test.m3u8",
        push_url="rtmp://127.0.0.1/live/room_test",
        category="技术",
        anchor_avatar="",
        cover_url="",
        online_count=0,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
        updated_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    repository.rooms[room.id] = room

    with pytest.raises(AppException) as error:
        service.start_room(room.id, owner_id=7)

    assert error.value.code == expected_code
    assert error.value.status_code == expected_status
    assert room.status == "preparing"


def test_only_owner_can_stop_and_stop_is_idempotent() -> None:
    repository = FakeRepository()
    service = LiveRoomService(repository, FakeMediaServer(True))
    room = LiveRoom(
        id=1,
        title="测试直播",
        anchor_user_id=7,
        anchor_name="主播",
        status="living",
        stream_name="room_test",
        play_url="http://127.0.0.1/live/room_test.m3u8",
        push_url="rtmp://127.0.0.1/live/room_test",
        category="技术",
        anchor_avatar="",
        cover_url="",
        online_count=1,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None),
        updated_at=datetime.now(timezone.utc).replace(tzinfo=None),
    )
    repository.rooms[room.id] = room

    with pytest.raises(AppException) as error:
        service.stop_room(room.id, owner_id=8)
    assert error.value.code == 40301
    assert room.status == "living"

    stopped = service.stop_room(room.id, owner_id=7)
    assert stopped.status == "ended"
    assert stopped.online_count == 0
    assert service.stop_room(room.id, owner_id=7).status == "ended"


def test_living_list_reconciles_streams_that_are_no_longer_published() -> None:
    repository = FakeRepository()
    service = LiveRoomService(repository, ReconcilingFakeMediaServer({"room_active"}))
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    active = LiveRoom(
        id=1,
        title="活动房间",
        anchor_user_id=7,
        anchor_name="主播",
        status="living",
        stream_name="room_active",
        play_url="http://127.0.0.1/live/room_active.m3u8",
        push_url="rtmp://127.0.0.1/live/room_active",
        category="技术",
        anchor_avatar="",
        cover_url="",
        online_count=1,
        created_at=now,
        updated_at=now,
    )
    stale = LiveRoom(
        id=2,
        title="失效房间",
        anchor_user_id=7,
        anchor_name="主播",
        status="living",
        stream_name="room_stale",
        play_url="http://127.0.0.1/live/room_stale.m3u8",
        push_url="rtmp://127.0.0.1/live/room_stale",
        category="技术",
        anchor_avatar="",
        cover_url="",
        online_count=1,
        created_at=now,
        updated_at=now,
    )
    repository.rooms = {1: active, 2: stale}

    rooms = service.get_living_rooms()

    assert [room.id for room in rooms] == [1]
    assert stale.status == "ended"
    assert stale.online_count == 0
