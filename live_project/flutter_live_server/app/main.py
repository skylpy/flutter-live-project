"""FastAPI 应用组装入口。

本文件只负责创建 App、注册中间件和异常处理器；具体业务接口位于
`app/api/v1/endpoints`，避免所有代码堆在一个文件中。
"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import SQLAlchemyError

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import check_database_connection
from app.core.exceptions import (
    AppException,
    app_exception_handler,
    database_exception_handler,
    unhandled_exception_handler,
    validation_exception_handler,
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """服务启动时检查 MySQL，但不阻止健康检查接口启动。"""
    if check_database_connection():
        logger.info("Database connection check succeeded")
    else:
        logger.warning("Database is unavailable; REST API will start but data endpoints need MySQL")
    yield


# 所有接口最终通过 api_router 挂载到 /api/v1 下，方便未来做版本升级。
app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    debug=settings.debug,
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "http://127.0.0.1", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# 统一异常处理保证客户端始终收到 {code, message, data} 结构。
app.add_exception_handler(AppException, app_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(SQLAlchemyError, database_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)
app.include_router(api_router)
