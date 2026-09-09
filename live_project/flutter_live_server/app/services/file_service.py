import logging
from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.exceptions import AppException, NotFoundException
from app.models.file import FileRecord
from app.models.social import DirectMessageMedia, FeedPostMedia
from app.schemas.file import FileResponse, UploadCompleteRequest, UploadSignatureRequest
from app.services.oss_service import OSSService
from app.utils.file_utils import validate_upload

logger = logging.getLogger(__name__)


def now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class FileService:
    def __init__(self, db: Session, oss: OSSService) -> None:
        self.db, self.oss = db, oss

    def sign_upload(self, user_id: int, request: UploadSignatureRequest) -> dict[str, Any]:
        validate_upload(
            request.filename,
            request.content_type,
            request.category,
            request.file_size,
            self.oss.config.oss_max_sizes,
        )
        key = self.oss.build_object_key(user_id, request.category, request.filename)
        signature = self.oss.generate_upload_signature(key, request.content_type, request.file_size)
        # 签发时保存 processing 意向，完成时只能确认此用户已签发的 key。
        self.db.add(
            FileRecord(
                user_id=user_id,
                object_key=key,
                original_filename=request.filename,
                content_type=request.content_type,
                file_size=request.file_size,
                category=request.category,
                status="processing",
                created_at=now(),
                updated_at=now(),
            )
        )
        self.db.commit()
        return signature

    def _owned(
        self,
        user_id: int,
        *,
        file_id: Optional[int] = None,
        key: Optional[str] = None,
        lock: bool = False,
    ) -> FileRecord:
        query = select(FileRecord).where(
            FileRecord.id == file_id if file_id is not None else FileRecord.object_key == key
        )
        if lock:
            query = query.with_for_update()
        record = self.db.scalar(query)
        if record is None:
            raise NotFoundException("文件记录不存在", 40440)
        if record.user_id != user_id:
            raise AppException("无权访问该文件", 40340, 403)
        return record

    def _active(self, user_id: int, file_id: int) -> FileRecord:
        record = self._owned(user_id, file_id=file_id)
        if record.status != "active":
            raise NotFoundException("文件尚未完成上传或已删除", 40440)
        return record

    def complete(self, user_id: int, request: UploadCompleteRequest) -> FileResponse:
        key = request.object_key
        parts = key.split("/")
        if len(parts) != 5 or parts[0] != "flutter" or ".." in key or "\\" in key:
            raise AppException("objectKey 非法", 40044, 400)
        if parts[2] != str(user_id):
            raise AppException("无权确认该文件", 40340, 403)
        record = self._owned(user_id, key=key, lock=True)
        if record.status == "deleted":
            raise NotFoundException("文件已删除", 40440)
        if (
            request.original_filename != record.original_filename
            or request.content_type != record.content_type
            or request.file_size != record.file_size
        ):
            raise AppException("上传信息与签发记录不匹配", 40045, 400)
        if record.status == "active":
            return self.response(record)
        if not self.oss.object_exists(key):
            raise NotFoundException("OSS 文件不存在，请先完成上传", 40441)
        metadata = self.oss.head_object(key)
        if (
            metadata.content_length != record.file_size
            or metadata.headers.get("Content-Type") != record.content_type
        ):
            raise AppException("OSS 文件大小或类型与签发记录不符", 40046, 400)
        record.status, record.updated_at = "active", now()
        self.db.commit()
        logger.info("File upload confirmed id=%s key=%s", record.id, key)
        return self.response(record)

    def response(self, record: FileRecord) -> FileResponse:
        return FileResponse.model_validate(record).model_copy(
            update={
                "url": self.oss.generate_download_url(record.object_key),
                "expire": self.oss.config.oss_sign_expire
                if self.oss.config.oss_use_signed_url
                else 0,
            }
        )

    def get(self, user_id: int, file_id: int) -> FileResponse:
        return self.response(self._active(user_id, file_id))

    def list_files(
        self, user_id: int, before_id: Optional[int] = None, limit: int = 30
    ) -> list[FileResponse]:
        query = select(FileRecord).where(
            FileRecord.user_id == user_id, FileRecord.status == "active"
        )
        if before_id is not None:
            query = query.where(FileRecord.id < before_id)
        # 列表不签发 URL；查看时再签发，避免大量临时链接和不必要的签名。
        return [
            FileResponse.model_validate(r)
            for r in self.db.scalars(query.order_by(FileRecord.id.desc()).limit(limit))
        ]

    def download(self, user_id: int, file_id: int) -> dict[str, Any]:
        record = self._active(user_id, file_id)
        return {
            "url": self.oss.generate_download_url(
                record.object_key, record.original_filename, True
            ),
            "expire": self.oss.config.oss_sign_expire if self.oss.config.oss_use_signed_url else 0,
            "filename": record.original_filename,
        }

    def delete(self, user_id: int, file_id: int) -> None:
        record = self._owned(user_id, file_id=file_id, lock=True)
        if record.status == "deleted":
            return
        if (
            self.db.scalar(
                select(FeedPostMedia.id).where(FeedPostMedia.file_id == record.id).limit(1)
            )
            is not None
        ):
            raise AppException("文件已用于动态，不能单独删除", 40941, 409)
        if (
            self.db.scalar(
                select(DirectMessageMedia.id)
                .where(DirectMessageMedia.file_id == record.id)
                .limit(1)
            )
            is not None
        ):
            raise AppException("文件已用于私信，不能单独删除", 40942, 409)
        self.oss.delete_object(record.object_key)
        record.status = "deleted"
        record.deleted_at = record.updated_at = now()
        self.db.commit()
        logger.info("File deleted id=%s key=%s", record.id, record.object_key)
