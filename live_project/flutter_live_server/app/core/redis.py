"""Optional Redis integration point for future realtime features."""

from typing import Any

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
