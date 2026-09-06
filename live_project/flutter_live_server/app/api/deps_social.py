from fastapi import Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.services.social_service import SocialService
from app.repositories.social_repository import SocialRepository


def get_social_service(db: Session = Depends(get_db)) -> SocialService:
    """组装动态、消息、资料和直播互动共用的 Service。"""
    return SocialService(SocialRepository(db))


def get_authenticated_user(user=Depends(get_current_user)):
    """给路由保留一个语义更清晰的当前用户依赖别名。"""
    return user
