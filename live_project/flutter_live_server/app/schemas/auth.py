from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class UserRegisterRequest(BaseModel):
    """注册请求，字段约束在进入 Service 前完成。"""

    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_]+$")
    password: str = Field(min_length=6, max_length=128)
    display_name: Optional[str] = Field(default=None, min_length=1, max_length=100)


class UserLoginRequest(BaseModel):
    """登录请求。"""

    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=6, max_length=128)


class UserResponse(BaseModel):
    """用户对外响应，不包含 password_hash。"""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    username: str
    display_name: str = Field(serialization_alias="displayName")


class AuthSessionResponse(BaseModel):
    """登录/注册成功返回的 JWT 会话。"""

    access_token: str = Field(serialization_alias="accessToken")
    token_type: str = Field(serialization_alias="tokenType")
    user: UserResponse
