from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user import User


class UserRepository:
    """用户数据库访问层。"""
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_username(self, username: str) -> Optional[User]:
        """按登录名查询用户。"""
        return self.db.scalar(select(User).where(User.username == username))

    def get_by_id(self, user_id: int) -> Optional[User]:
        """按用户 ID 查询用户。"""
        return self.db.get(User, user_id)

    def create(self, user: User) -> User:
        """插入用户并刷新对象，使调用方拿到数据库生成的 ID。"""
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user
