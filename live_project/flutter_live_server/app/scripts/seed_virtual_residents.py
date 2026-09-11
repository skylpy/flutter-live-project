"""写入可重复执行的虚拟居民与初始动态。

不依赖 DeepSeek 密钥：先完成迁移并执行本脚本，之后填写密钥、重启 FastAPI，
直播间才会开始由这些已有角色进行低频实时互动。
"""

from __future__ import annotations

import secrets
from datetime import datetime, timezone

from sqlalchemy import select

from app.core.database import SessionLocal
from app.core.security import hash_password
from app.models.ai import VirtualResidentProfile
from app.models.social import FeedPost, FeedPostMedia
from app.models.user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


RESIDENTS = (
    {
        "username": "virtual_xiaoman",
        "display_name": "小满",
        "role": "warm_companion",
        "persona": "喜欢认真听别人说完的晚间聊天搭子，温柔但不黏人。",
        "interests": "晚安、心事、音乐、日常、情绪",
        "speaking_style": "短句，有一点生活感，偶尔用🌙，不滥用表情。",
        "post": "傍晚的风比想象中凉一点，耳机里刚好放到一首适合慢慢走路的歌。",
        "media": ("/static/ai_bots/rainy_cafe.jpg", "image"),
    },
    {
        "username": "virtual_tingyu",
        "display_name": "听雨",
        "role": "music_fan",
        "persona": "偏爱现场音乐和旧歌的安静观众，听歌时比说话时多。",
        "interests": "音乐、歌单、现场、吉他、夜晚",
        "speaking_style": "自然、简洁，会说具体听感，不做浮夸夸赞。",
        "post": "今天循环的是一张旧歌单。前奏一响，很多没说出口的话就有地方放了。",
    },
    {
        "username": "virtual_youzi",
        "display_name": "柚子汽水",
        "role": "lively_friend",
        "persona": "有一点俏皮的生活分享者，擅长把尴尬的冷场轻轻接住。",
        "interests": "美食、电影、旅行、日常、聊天",
        "speaking_style": "轻快但不刷屏，偶尔自嘲，不使用网络烂梗。",
        "post": "下班路上买到一瓶冰柚子汽水。第一口是今天最明确的“我下班了”。",
    },
    {
        "username": "virtual_xingye",
        "display_name": "星野",
        "role": "game_buddy",
        "persona": "喜欢游戏和数码的夜猫子，乐于分享小技巧但不说教。",
        "interests": "游戏、开黑、数码、键盘、直播",
        "speaking_style": "直爽、有分寸，遇到新手会耐心解释。",
        "post": "新键盘到手的第一晚，明明只是换了几个键帽，敲字却像换了一个心情。",
        "media": ("/static/ai_bots/keyboard_night.jpg", "image"),
    },
    {
        "username": "virtual_xiaobei",
        "display_name": "小北",
        "role": "photo_observer",
        "persona": "爱拍城市光影的观察者，会注意画面里不经意的小细节。",
        "interests": "摄影、夜景、咖啡、展览、城市",
        "speaking_style": "安静具体，常从颜色、光线和气味切入。",
        "post": "路灯亮起来那一刻，玻璃窗里的倒影突然比街道本身更像一场电影。",
        "media": ("/static/ai_bots/night_bus.jpg", "image"),
    },
    {
        "username": "virtual_wanfeng",
        "display_name": "晚风电台",
        "role": "radio_host",
        "persona": "深夜电台的虚拟主持人，擅长把话题留给每一个愿意开口的人。",
        "interests": "电台、点歌、晚安、故事、陪伴",
        "speaking_style": "温和、有停顿感，避免过度亲密或情感承诺。",
        "post": "今晚的电台想留一个问题：最近有没有一件很小、但让你高兴很久的事？",
    },
)


def seed() -> None:
    db = SessionLocal()
    try:
        now = _utcnow()
        created_users = 0
        created_posts = 0
        linked_media = 0
        for resident in RESIDENTS:
            user = db.scalar(select(User).where(User.username == resident["username"]))
            if user is None:
                user = User(
                    username=resident["username"],
                    # 虚拟账号没有可分发的登录密码；随机哈希仅满足用户表约束。
                    password_hash=hash_password(secrets.token_urlsafe(32)),
                    display_name=resident["display_name"],
                    is_active=True,
                    is_virtual=True,
                    created_at=now,
                    updated_at=now,
                )
                db.add(user)
                db.flush()
                created_users += 1
            else:
                user.display_name = resident["display_name"]
                user.is_virtual = True
                user.is_active = True
                user.updated_at = now

            profile = db.scalar(
                select(VirtualResidentProfile).where(VirtualResidentProfile.user_id == user.id)
            )
            if profile is None:
                profile = VirtualResidentProfile(
                    user_id=user.id,
                    role=resident["role"],
                    persona=resident["persona"],
                    interests=resident["interests"],
                    speaking_style=resident["speaking_style"],
                    is_enabled=True,
                    created_at=now,
                    updated_at=now,
                )
                db.add(profile)
            else:
                profile.role = resident["role"]
                profile.persona = resident["persona"]
                profile.interests = resident["interests"]
                profile.speaking_style = resident["speaking_style"]
                profile.is_enabled = True
                profile.updated_at = now

            post = db.scalar(
                select(FeedPost).where(
                    FeedPost.author_id == user.id,
                    FeedPost.body == resident["post"],
                )
            )
            if post is None:
                db.add(
                    FeedPost(
                        author_id=user.id,
                        body=resident["post"],
                        media_kind=resident.get("media", ("", "none"))[1],
                        likes_count=0,
                        comments_count=0,
                        shares_count=0,
                        created_at=now,
                        updated_at=now,
                    )
                )
                db.flush()
                post = db.scalar(
                    select(FeedPost).where(
                        FeedPost.author_id == user.id,
                        FeedPost.body == resident["post"],
                    )
                )
                created_posts += 1

            media = resident.get("media")
            if post is not None and media is not None:
                source_url, media_type = media
                post.media_kind = media_type
                existing_media = db.scalar(
                    select(FeedPostMedia).where(
                        FeedPostMedia.post_id == post.id,
                        FeedPostMedia.source_url == source_url,
                    )
                )
                if existing_media is None:
                    db.add(
                        FeedPostMedia(
                            post_id=post.id,
                            file_id=None,
                            source_url=source_url,
                            media_type=media_type,
                            sort_order=0,
                            created_at=now,
                        )
                    )
                    linked_media += 1

        db.commit()
        print(
            "虚拟居民已就绪："
            f"新增 {created_users} 个账号、{created_posts} 条动态、{linked_media} 个媒体素材"
        )
    finally:
        db.close()


if __name__ == "__main__":
    seed()
