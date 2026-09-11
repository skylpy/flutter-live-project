"""写入一组可重复执行的 Phase 2 本地验收数据。

脚本只服务本地开发环境，不参与线上启动流程。它使用固定的正文前缀判断
是否已经写入过，因此重复执行不会不断制造重复动态或消息。
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.social import DirectMessage, FeedPost
from app.models.user import User


def seed() -> None:
    db = SessionLocal()
    try:
        users = db.scalars(select(User).order_by(User.id)).all()
        if not users:
            raise RuntimeError("数据库中还没有用户，请先注册一个账号")

        author = users[0]
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        bodies = [
            "[Phase2 验收] 今天的直播间已经接入真实动态 Repository。",
            "[Phase2 验收] 点赞会写入数据库，刷新后仍然保留状态。",
            "[Phase2 验收] 这条动态用于 Android 模拟器登录后的链路检查。",
        ]
        for index, body in enumerate(bodies):
            exists = db.scalar(select(FeedPost).where(FeedPost.body == body))
            if exists is None:
                db.add(
                    FeedPost(
                        author_id=author.id,
                        body=body,
                        media_kind="none",
                        likes_count=0,
                        comments_count=0,
                        shares_count=0,
                        created_at=now - timedelta(minutes=index),
                        updated_at=now - timedelta(minutes=index),
                    )
                )

        # 至少有两个账号时补一条真实会话，供消息页验收；只有一个账号时
        # 动态仍可完整验证，脚本不会为了演示数据创建额外账号。
        if len(users) >= 2:
            sender, recipient = users[0], users[1]
            message_body = "[Phase2 验收] 这是一条来自真实后端的消息。"
            exists = db.scalar(
                select(DirectMessage).where(DirectMessage.body == message_body)
            )
            if exists is None:
                db.add(
                    DirectMessage(
                        sender_id=sender.id,
                        recipient_id=recipient.id,
                        body=message_body,
                        is_read=False,
                        created_at=now,
                    )
                )

        db.commit()
        print("Phase 2 本地验收数据已准备完成")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
