from datetime import datetime, timedelta, timezone

import jwt
from pwdlib import PasswordHash

from .config import settings

password_hasher = PasswordHash.recommended()


def build_bearer_token_header(token: str) -> dict[str, str]:
    """给测试或客户端示例生成标准 Bearer 请求头。"""
    return {"Authorization": f"Bearer {token}"}


def hash_password(password: str) -> str:
    """使用 pwdlib 推荐算法保存密码哈希，而不是保存明文密码。"""
    return password_hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """验证用户输入的密码是否匹配数据库中的哈希。"""
    return password_hasher.verify(password, password_hash)


def create_access_token(user_id: int, username: str) -> str:
    """创建包含用户标识和过期时间的 JWT。"""
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {"sub": str(user_id), "username": username, "exp": expires_at}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict[str, object]:
    """解码并校验 JWT；签名或过期无效时由 PyJWT 抛出异常。"""
    return jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
