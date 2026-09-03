"""Redis clients for phase-two realtime features."""

from functools import lru_cache
from typing import Any

from redis.asyncio import Redis, from_url

from .config import settings


def get_redis_config() -> dict[str, Any]:
    return {
        "host": settings.redis_host,
        "port": settings.redis_port,
        "db": settings.redis_db,
    }


def get_redis_client() -> Any:
    """Create a client only when a future feature explicitly needs Redis."""
    try:
        import redis
    except ImportError as exc:
        raise RuntimeError("Redis dependency is not installed") from exc
    return redis.Redis(**get_redis_config(), decode_responses=True)


@lru_cache
def get_async_redis() -> Redis:
    return from_url(settings.redis_url, decode_responses=True)
