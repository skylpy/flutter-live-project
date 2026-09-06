from __future__ import annotations

from time import monotonic, sleep
from typing import Any

import httpx

from app.core.config import settings


class MediaServerClient:
    """读取 SRS 控制 API 的最小客户端。

    FastAPI 只保存直播间的控制面状态，真正的音视频连接由 SRS 管理。因此
    主播端上报“推流成功”后，服务端还要确认 SRS 看到 active publish，避免
    观众列表出现一个数据库显示 living、实际却没有画面的房间。
    """

    def __init__(self) -> None:
        self._url = (
            f"http://{settings.media_internal_host}:{settings.media_internal_api_port}"
            "/api/v1/streams/"
        )

    def active_stream_names(self) -> set[str] | None:
        """返回 SRS 明确标记为 publish.active 的流名称。

        None 和空集合必须区分：空集合表示 SRS 明确没有活动流，None 表示
        控制 API 暂时不可用，调用方可以据此决定是否进入保护性重试。
        """
        try:
            response = httpx.get(self._url, timeout=1.0)
            response.raise_for_status()
            payload = response.json()
        # 某些 macOS 自带 Python 的证书路径可能损坏，即使请求目标是 HTTP，
        # httpx 初始化客户端时也会尝试加载 SSL 默认上下文。此时把探针视为
        # “暂不可用”而不是让直播列表接口整体返回 500。
        except (httpx.HTTPError, ValueError, OSError):
            return None

        streams = payload.get("streams")
        if not isinstance(streams, list):
            return None
        names: set[str] = set()
        for stream in streams:
            if not isinstance(stream, dict):
                continue
            name = stream.get("name")
            publish = stream.get("publish")
            if isinstance(name, str) and isinstance(publish, dict) and publish.get("active") is True:
                names.add(name)
        return names

    def wait_for_active_stream(self, stream_name: str) -> bool | None:
        """在有限窗口内等待 SRS 看到指定 stream_name。

        True 是确认成功，False 是 SRS 可用但超时未看到，None 是 SRS 控制 API
        不可用。这样不会把基础设施短暂故障误判成主播推流失败。
        """
        deadline = monotonic() + settings.live_room_reconciliation_grace_seconds
        while monotonic() < deadline:
            active_names = self.active_stream_names()
            if active_names is None:
                return None
            if stream_name in active_names:
                return True
            sleep(0.25)
        return False
