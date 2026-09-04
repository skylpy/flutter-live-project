from typing import Optional

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.repositories.live_room_repository import LiveRoomRepository
from app.repositories.user_repository import UserRepository
from app.services.auth_service import AuthService
from app.services.live_room_service import LiveRoomService

# HTTPBearer 只负责读取 Authorization；Token 的签名校验在 get_current_user 完成。
bearer_scheme = HTTPBearer(auto_error=False)


def get_live_room_service(db: Session = Depends(get_db)) -> LiveRoomService:
    """组装直播房间 Service，供路由通过 Depends 注入。"""
    return LiveRoomService(LiveRoomRepository(db))


def get_auth_service(db: Session = Depends(get_db)) -> AuthService:
    """组装认证 Service，避免路由自己管理数据库对象。"""
    return AuthService(UserRepository(db))


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    """校验 Bearer JWT 并加载当前用户；受保护接口复用这一依赖。"""
    from app.core.config import settings
    from app.core.exceptions import AppException

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppException("请先登录", code=40100, status_code=401)
    try:
        # JWT 只证明 Token 未被篡改且未过期，仍需查询数据库确认用户存在且启用。
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )
        user_id = int(payload.get("sub", 0))
    except (ValueError, TypeError, jwt.InvalidTokenError) as exc:
        raise AppException("登录凭证无效或已过期", code=40100, status_code=401) from exc

    user = UserRepository(db).get_by_id(user_id)
    if user is None or not user.is_active:
        raise AppException("用户不存在或已停用", code=40102, status_code=401)
    return user
