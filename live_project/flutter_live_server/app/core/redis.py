"""Redis 客户端和实时功能的基础配置。

Redis 用于在线人数集合和跨进程 Pub/Sub；视频本身不会经过 Redis。
"""

from functools import lru_cache
from typing import Any

from redis.asyncio import Redis, from_url

from .config import settings


def get_redis_config() -> dict[str, Any]:
    """返回同步客户端需要的连接参数。"""
    return {
        "host": settings.redis_host,
        "port": settings.redis_port,
        "db": settings.redis_db,
    }


def get_redis_client() -> Any:
    """按需创建同步客户端，供脚本或同步代码使用。"""
    try:
        import redis
    except ImportError as exc:
        raise RuntimeError("Redis dependency is not installed") from exc
    return redis.Redis(**get_redis_config(), decode_responses=True)


@lru_cache
def get_async_redis() -> Redis:
    """缓存一个异步 Redis 客户端，供 WebSocket 任务复用。"""
    return from_url(settings.redis_url, decode_responses=True)
