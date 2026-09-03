from fastapi import APIRouter

from app.api.v1.endpoints import auth, health, live, realtime

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(live.router)
api_router.include_router(auth.router)
api_router.include_router(realtime.router)
