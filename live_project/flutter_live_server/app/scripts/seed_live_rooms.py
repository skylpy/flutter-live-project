from datetime import datetime, timezone

from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.live_room import LiveRoom

SEED_ROOMS = (
    {"title": "一起聊聊 Flutter", "anchor_name": "小林", "online_count": 12800, "category": "科技"},
    {"title": "深夜音乐直播间", "anchor_name": "Summer", "online_count": 8260, "category": "音乐"},
    {"title": "游戏娱乐直播", "anchor_name": "Kevin", "online_count": 5630, "category": "游戏"},
    {"title": "Flutter 插件开发", "anchor_name": "Leo", "online_count": 3680, "category": "技术"},
)


def seed_live_rooms() -> int:
    inserted = 0
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    with SessionLocal() as db:
        for room_data in SEED_ROOMS:
            statement = select(LiveRoom).where(
                LiveRoom.title == room_data["title"],
                LiveRoom.anchor_name == room_data["anchor_name"],
            )
            if db.scalar(statement) is not None:
                continue
            db.add(
                LiveRoom(
                    **room_data,
                    anchor_avatar="",
                    cover_url="",
                    status="living",
                    play_url="",
                    created_at=now,
                    updated_at=now,
                )
            )
            inserted += 1
        db.commit()
    return inserted


if __name__ == "__main__":
    print(f"Inserted {seed_live_rooms()} live room(s).")
