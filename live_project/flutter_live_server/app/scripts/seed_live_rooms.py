from datetime import datetime, timezone

from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.live_room import LiveRoom

# 仅供开发和真机验收使用的公开 HLS 测试流。
# 生产环境必须由直播业务或 CDN 返回真实 play_url，不能依赖这个地址。
DEMO_HLS_URL = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"

SEED_ROOMS = (
    {
        "title": "一起聊聊 Flutter",
        "anchor_name": "小林",
        "online_count": 12800,
        "category": "科技",
        "play_url": DEMO_HLS_URL,
    },
    {
        "title": "深夜音乐直播间",
        "anchor_name": "Summer",
        "online_count": 8260,
        "category": "音乐",
        "play_url": DEMO_HLS_URL,
    },
    {
        "title": "游戏娱乐直播",
        "anchor_name": "Kevin",
        "online_count": 5630,
        "category": "游戏",
        "play_url": DEMO_HLS_URL,
    },
    {
        "title": "Flutter 插件开发",
        "anchor_name": "Leo",
        "online_count": 3680,
        "category": "技术",
        "play_url": DEMO_HLS_URL,
    },
)


def seed_live_rooms() -> int:
    """幂等写入四条演示直播间，已存在的房间不会重复插入。"""
    inserted = 0
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    with SessionLocal() as db:
        for room_data in SEED_ROOMS:
            statement = select(LiveRoom).where(
                LiveRoom.title == room_data["title"],
                LiveRoom.anchor_name == room_data["anchor_name"],
            )
            existing = db.scalar(statement)
            if existing is not None:
                # 之前已执行过旧版 seed 时，房间可能仍是空播放地址；只在空值时
                # 补上测试流，不覆盖开发者已经配置的真实地址。
                if not existing.play_url:
                    existing.play_url = room_data["play_url"]
                    existing.updated_at = now
                continue
            db.add(
                LiveRoom(
                    **room_data,
                    anchor_avatar="",
                    cover_url="",
                    status="living",
                    created_at=now,
                    updated_at=now,
                )
            )
            inserted += 1
        db.commit()
    return inserted


if __name__ == "__main__":
    print(f"Inserted {seed_live_rooms()} live room(s).")
