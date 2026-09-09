from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class UploadSignatureRequest(BaseModel):
    filename: str = Field(min_length=1, max_length=255, description="原始文件名，不能包含路径")
    content_type: str = Field(max_length=128, description="与文件扩展名匹配的 MIME 类型")
    category: str = Field(
        max_length=20, description="source/image/avatar/pdf/audio/video/result/document"
    )
    file_size: int = Field(description="文件字节数；按分类限制大小")


class UploadSignature(BaseModel):
    object_key: str
    upload_url: str
    method: Literal["PUT"] = "PUT"
    headers: dict[str, str]
    expire: int


class UploadCompleteRequest(BaseModel):
    object_key: str = Field(
        min_length=1, max_length=512, description="签名接口原样返回的 object_key"
    )
    original_filename: str = Field(
        min_length=1, max_length=255, description="签名时提交的原始文件名"
    )
    content_type: str = Field(max_length=128, description="签名时提交的 MIME 类型")
    file_size: int = Field(gt=0, description="签名时提交的文件字节数")


class FileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    object_key: str
    original_filename: str
    content_type: str
    file_size: int
    category: str
    status: str
    created_at: datetime
    updated_at: datetime
    url: Optional[str] = None
    expire: int = 0


class DownloadUrlResponse(BaseModel):
    url: str
    expire: int
    filename: str
