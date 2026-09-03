from typing import Generic, Optional, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    code: int = 0
    message: str = "success"
    data: Optional[T] = None


def success(data: T, message: str = "success") -> ApiResponse[T]:
    return ApiResponse(code=0, message=message, data=data)
