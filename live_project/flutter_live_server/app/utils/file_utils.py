"""文件类型策略；路径和对象名永远由服务端控制。"""

from pathlib import PurePosixPath

from app.core.exceptions import AppException

MIME_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "heic": "image/heic",
    "pdf": "application/pdf",
    "mp3": "audio/mpeg",
    "m4a": "audio/mp4",
    "wav": "audio/wav",
    "aac": "audio/aac",
    "mp4": "video/mp4",
    "mov": "video/quicktime",
    "txt": "text/plain",
    "doc": "application/msword",
    "xls": "application/vnd.ms-excel",
    "ppt": "application/vnd.ms-powerpoint",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
}
EXTENSIONS = {
    "image": {"jpg", "jpeg", "png", "webp", "heic"},
    "avatar": {"jpg", "jpeg", "png", "webp", "heic"},
    "pdf": {"pdf"},
    "audio": {"mp3", "m4a", "wav", "aac"},
    "video": {"mp4", "mov"},
    "document": {"doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt"},
    "source": set(MIME_TYPES),
    "result": set(MIME_TYPES),
}


def validate_filename(filename: str) -> str:
    if (
        not filename
        or len(filename) > 255
        or ".." in filename
        or any(c in filename for c in "/\\")
        or any(ord(c) < 32 or ord(c) == 127 for c in filename)
    ):
        raise AppException("文件名非法", code=40040, status_code=400)
    return PurePosixPath(filename).suffix.lower().lstrip(".")


def validate_upload(
    filename: str, content_type: str, category: str, file_size: int, limits: dict[str, int]
) -> None:
    extension = validate_filename(filename)
    if category not in EXTENSIONS:
        raise AppException("文件分类不允许", code=40041, status_code=400)
    if extension not in EXTENSIONS[category] or MIME_TYPES.get(extension) != content_type:
        raise AppException("文件扩展名或内容类型不允许", code=40042, status_code=400)
    if file_size <= 0:
        raise AppException("不能上传空文件", code=40043, status_code=400)
    if file_size > limits.get(category, 0):
        raise AppException("文件超过该分类的大小限制", code=41340, status_code=413)
