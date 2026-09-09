"""OSS 控制面。文件字节由客户端直接 PUT/GET，禁止经 FastAPI 中转。"""

import logging
import re
from collections.abc import Callable
from datetime import datetime, timezone
from functools import lru_cache
from typing import Any, Optional, TypeVar
from urllib.parse import quote, urlsplit
from uuid import uuid4

import oss2

from app.core.config import Settings, settings
from app.core.exceptions import AppException
from app.utils.file_utils import EXTENSIONS, validate_filename

logger = logging.getLogger(__name__)
T = TypeVar("T")


class OSSService:
    def __init__(self, config: Settings = settings, bucket: Optional[oss2.Bucket] = None) -> None:
        self.config = config
        self._bucket = bucket

    def check_configuration(self) -> None:
        missing = [
            key.upper()
            for key in (
                "oss_access_key_id",
                "oss_access_key_secret",
                "oss_endpoint",
                "oss_bucket",
            )
            if not (
                getattr(self.config, key).get_secret_value()
                if key in {"oss_access_key_id", "oss_access_key_secret"}
                else getattr(self.config, key)
            )
        ]
        if missing:
            raise AppException("OSS 配置缺失：" + ", ".join(missing), 50340, 503)
        endpoint = urlsplit(self.config.oss_endpoint)
        if (
            endpoint.scheme != "https"
            or not endpoint.hostname
            or endpoint.username
            or endpoint.query
            or endpoint.fragment
            or endpoint.path not in {"", "/"}
        ):
            raise AppException("OSS_ENDPOINT 必须是 HTTPS 服务地址", 50340, 503)

    @property
    def bucket(self) -> oss2.Bucket:
        if self._bucket is None:
            self.check_configuration()
            self._bucket = oss2.Bucket(
                oss2.AuthV4(
                    self.config.oss_access_key_id.get_secret_value(),
                    self.config.oss_access_key_secret.get_secret_value(),
                ),
                self.config.oss_endpoint,
                self.config.oss_bucket,
                region=self.config.oss_region.removeprefix("oss-"),
                connect_timeout=15,
            )
        return self._bucket

    def _call(self, operation: str, object_key: str, callback: Callable[[], T]) -> T:
        try:
            result = callback()
            logger.info("OSS %s key=%s", operation, object_key)
            return result
        except oss2.exceptions.OssError as exc:
            # SDK 异常可能含签名 URL；只记录类型和状态，不输出异常正文。
            logger.warning(
                "OSS %s failed key=%s type=%s status=%s",
                operation,
                object_key,
                type(exc).__name__,
                getattr(exc, "status", None),
            )
            raise AppException("OSS 服务暂不可用，请稍后重试", 50240, 502) from None

    def build_object_key(self, user_id: int, category: str, filename: str) -> str:
        extension = validate_filename(filename)
        if category not in EXTENSIONS or extension not in EXTENSIONS[category]:
            raise AppException("文件分类或扩展名不允许", 40041, 400)
        directory = getattr(self.config, f"oss_{category}_dir", category)
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", directory):
            raise AppException("OSS 目录配置非法", 50340, 503)
        day = datetime.now(timezone.utc).strftime("%Y%m%d")
        return f"flutter/{directory}/{user_id}/{day}/{uuid4()}.{extension}"

    def generate_upload_signature(
        self, object_key: str, content_type: str, file_size: int
    ) -> dict[str, Any]:
        headers = {
            "Content-Type": content_type,
            "Content-Length": str(file_size),
            "x-oss-forbid-overwrite": "true",
        }
        url = self._call(
            "sign-put",
            object_key,
            lambda: self.bucket.sign_url(
                "PUT",
                object_key,
                self.config.oss_sign_expire,
                headers=headers,
                additional_headers={"content-length"},
                slash_safe=True,
            ),
        )
        return {
            "object_key": object_key,
            "upload_url": url,
            "method": "PUT",
            "headers": headers,
            "expire": self.config.oss_sign_expire,
        }

    def generate_upload_url(self, object_key: str, content_type: str, file_size: int) -> str:
        return self.generate_upload_signature(object_key, content_type, file_size)["upload_url"]

    def generate_download_url(
        self, object_key: str, filename: str = "", attachment: bool = False
    ) -> str:
        if not self.config.oss_use_signed_url:
            host = urlsplit(self.config.oss_endpoint).netloc
            return f"https://{self.config.oss_bucket}.{host}/{quote(object_key, safe='/')}"
        params = {}
        if attachment:
            params["response-content-disposition"] = "attachment; filename*=UTF-8''" + quote(
                filename, safe=""
            )
        return self._call(
            "sign-get",
            object_key,
            lambda: self.bucket.sign_url(
                "GET",
                object_key,
                self.config.oss_sign_expire,
                params=params,
                slash_safe=True,
            ),
        )

    def object_exists(self, object_key: str) -> bool:
        return self._call("exists", object_key, lambda: self.bucket.object_exists(object_key))

    def head_object(self, object_key: str) -> oss2.models.HeadObjectResult:
        return self._call("head", object_key, lambda: self.bucket.head_object(object_key))

    def delete_object(self, object_key: str) -> None:
        self._call("delete", object_key, lambda: self.bucket.delete_object(object_key))

    def cleanup_orphan_objects(self) -> None:
        # TODO: 按 processing 记录、日期及用户目录清理过期孤儿文件；需等待签名失效。
        raise NotImplementedError("孤儿文件定时清理尚未启用")


@lru_cache
def get_oss_service() -> OSSService:
    return OSSService()
