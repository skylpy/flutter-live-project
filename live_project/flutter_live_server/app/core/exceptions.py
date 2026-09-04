from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppException(Exception):
    """可以安全返回给客户端的业务异常。"""

    def __init__(self, message: str, code: int = 50000, status_code: int = 500) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


class NotFoundException(AppException):
    """资源不存在时使用的 404 业务异常。"""

    def __init__(self, message: str = "资源不存在", code: int = 40400) -> None:
        super().__init__(message=message, code=code, status_code=404)


def error_payload(code: int, message: str) -> dict[str, Any]:
    """构造统一错误响应体。"""
    return {"code": code, "message": message, "data": None}


async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    """把已知业务异常转换为 JSON。"""
    return JSONResponse(status_code=exc.status_code, content=error_payload(exc.code, exc.message))


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """把 Pydantic 请求校验错误转换为统一格式。"""
    return JSONResponse(status_code=422, content=error_payload(42200, "请求数据校验失败"))


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """隐藏内部异常细节，避免把堆栈信息泄露给客户端。"""
    return JSONResponse(status_code=500, content=error_payload(50000, "服务器内部错误"))


async def database_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """数据库异常的统一兜底响应。"""
    return JSONResponse(status_code=503, content=error_payload(50301, "数据库暂不可用"))
