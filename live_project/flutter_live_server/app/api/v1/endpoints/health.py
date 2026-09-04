from fastapi import APIRouter

from app.core.database import check_database_connection
from app.schemas.common import ApiResponse, success

router = APIRouter(tags=["health"])


@router.get("/health", response_model=ApiResponse[dict[str, str]])
def health() -> ApiResponse[dict[str, str]]:
    """返回服务和 MySQL 的最小运行状态，供启动检查和监控使用。"""
    database_status = "connected" if check_database_connection() else "unavailable"
    return success(
        {
            "status": "ok",
            "service": "flutter-live-server",
            "database": database_status,
        }
    )
