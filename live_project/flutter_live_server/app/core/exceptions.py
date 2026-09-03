from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppException(Exception):
    def __init__(self, message: str, code: int = 50000, status_code: int = 500) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


class NotFoundException(AppException):
    def __init__(self, message: str = "资源不存在", code: int = 40400) -> None:
        super().__init__(message=message, code=code, status_code=404)


def error_payload(code: int, message: str) -> dict[str, Any]:
    return {"code": code, "message": message, "data": None}


async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content=error_payload(exc.code, exc.message))


async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(status_code=422, content=error_payload(42200, "请求数据校验失败"))


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=500, content=error_payload(50000, "服务器内部错误"))


async def database_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=503, content=error_payload(50301, "数据库暂不可用"))
