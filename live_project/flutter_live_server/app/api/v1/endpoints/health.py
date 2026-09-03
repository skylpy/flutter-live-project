from fastapi import APIRouter

from app.core.database import check_database_connection
from app.schemas.common import ApiResponse, success

router = APIRouter(tags=["health"])


@router.get("/health", response_model=ApiResponse[dict[str, str]])
def health() -> ApiResponse[dict[str, str]]:
    database_status = "connected" if check_database_connection() else "unavailable"
    return success(
        {
            "status": "ok",
            "service": "flutter-live-server",
            "database": database_status,
        }
    )
