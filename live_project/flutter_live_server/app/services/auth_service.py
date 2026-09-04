from datetime import datetime, timezone

from app.core.exceptions import AppException
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.auth import AuthSessionResponse, UserRegisterRequest


class AuthService:
    """认证业务层：注册、登录、Token 会话和用户状态校验。"""

    def __init__(self, repository: UserRepository) -> None:
        self.repository = repository

    def register(self, request: UserRegisterRequest) -> AuthSessionResponse:
        """创建用户、哈希密码并立即签发 JWT。"""
        if self.repository.get_by_username(request.username) is not None:
            raise AppException("用户名已存在", code=40901, status_code=409)
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        user = self.repository.create(
            User(
                username=request.username,
                password_hash=hash_password(request.password),
                display_name=request.display_name or request.username,
                created_at=now,
                updated_at=now,
            )
        )
        return self._session(user)

    def login(self, username: str, password: str) -> AuthSessionResponse:
        """校验登录凭证，成功后创建会话。"""
        user = self.repository.get_by_username(username)
        if user is None or not user.is_active or not verify_password(password, user.password_hash):
            raise AppException("用户名或密码错误", code=40101, status_code=401)
        return self._session(user)

    def get_user(self, user_id: int) -> User:
        """读取并校验用户仍处于可用状态。"""
        user = self.repository.get_by_id(user_id)
        if user is None or not user.is_active:
            raise AppException("用户不存在或已停用", code=40102, status_code=401)
        return user

    def _session(self, user: User) -> AuthSessionResponse:
        """把用户转换成统一的 Token + 用户资料响应。"""
        return AuthSessionResponse(
            access_token=create_access_token(user.id, user.username),
            token_type="bearer",
            user=user,
        )
