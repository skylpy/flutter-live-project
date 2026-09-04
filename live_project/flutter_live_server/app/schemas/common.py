from typing import Generic, Optional, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    """所有 HTTP 接口共用的响应包装。

    code=0 表示业务成功；data 的类型由泛型 T 决定，客户端可以统一解析。
    """

    code: int = 0
    message: str = "success"
    data: Optional[T] = None


def success(data: T, message: str = "success") -> ApiResponse[T]:
    """构造成功响应，避免每个路由重复填写 code。"""
    return ApiResponse(code=0, message=message, data=data)
