from fastapi import APIRouter

from app.api.v1.endpoints import auth, health, live, realtime

# 路由模块只做 URL 组织；真正的处理逻辑留在各 endpoint 和 service 中。
api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(live.router)
api_router.include_router(auth.router)
api_router.include_router(realtime.router)
