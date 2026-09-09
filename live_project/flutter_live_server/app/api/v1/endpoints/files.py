from typing import Optional

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.schemas.common import ApiResponse, success
from app.schemas.file import (
    DownloadUrlResponse,
    FileResponse,
    UploadCompleteRequest,
    UploadSignature,
    UploadSignatureRequest,
)
from app.services.file_service import FileService
from app.services.oss_service import OSSService, get_oss_service


def private_response(response: Response):
    response.headers["Cache-Control"] = "no-store"


router = APIRouter(prefix="/files", tags=["files"], dependencies=[Depends(private_response)])


def get_file_service(db: Session = Depends(get_db), oss: OSSService = Depends(get_oss_service)):
    return FileService(db, oss)


@router.post("/upload-signature", response_model=ApiResponse[UploadSignature])
def upload_signature(
    request: UploadSignatureRequest,
    user=Depends(get_current_user),
    service: FileService = Depends(get_file_service),
):
    return success(service.sign_upload(user.id, request))


@router.post("/upload-complete", response_model=ApiResponse[FileResponse])
def upload_complete(
    request: UploadCompleteRequest,
    user=Depends(get_current_user),
    service: FileService = Depends(get_file_service),
):
    return success(service.complete(user.id, request))


@router.get("", response_model=ApiResponse[list[FileResponse]])
def list_files(
    before_id: Optional[int] = Query(None, gt=0),
    limit: int = Query(30, ge=1, le=100),
    user=Depends(get_current_user),
    service: FileService = Depends(get_file_service),
):
    return success(service.list_files(user.id, before_id, limit))


@router.get("/{file_id}", response_model=ApiResponse[FileResponse])
def get_file(
    file_id: int, user=Depends(get_current_user), service: FileService = Depends(get_file_service)
):
    return success(service.get(user.id, file_id))


@router.get("/{file_id}/download-url", response_model=ApiResponse[DownloadUrlResponse])
def download_url(
    file_id: int, user=Depends(get_current_user), service: FileService = Depends(get_file_service)
):
    return success(service.download(user.id, file_id))


@router.delete("/{file_id}", response_model=ApiResponse[None])
def delete_file(
    file_id: int, user=Depends(get_current_user), service: FileService = Depends(get_file_service)
):
    service.delete(user.id, file_id)
    return success(None)
