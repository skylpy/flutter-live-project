from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import Mock
from urllib.parse import parse_qs, urlsplit

import oss2
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.deps import get_current_user
from app.api.v1.endpoints.files import get_file_service
from app.core.config import Settings
from app.core.database import get_db
from app.core.exceptions import AppException
from app.main import app
from app.models.base import Base
from app.models.file import FileRecord
from app.models.social import DirectMessage, DirectMessageMedia, FeedPost, FeedPostMedia
from app.models.user import User
from app.services.file_service import FileService
from app.services.oss_service import OSSService


@pytest.fixture
def api():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            FileRecord.__table__,
            DirectMessage.__table__,
            DirectMessageMedia.__table__,
            FeedPost.__table__,
            FeedPostMedia.__table__,
        ],
    )
    with Session(engine) as db:
        for user_id in (1, 2):
            db.add(
                User(
                    id=user_id,
                    username=f"user{user_id}",
                    password_hash="unused",
                    display_name="测试",
                    is_active=True,
                    created_at=datetime.now(timezone.utc),
                    updated_at=datetime.now(timezone.utc),
                )
            )
        db.commit()
        bucket = Mock()
        bucket.sign_url.return_value = "https://example.invalid/signed"
        bucket.object_exists.return_value = True
        bucket.head_object.return_value = SimpleNamespace(
            content_length=123, headers={"Content-Type": "image/jpeg"}
        )
        oss = OSSService(Settings(_env_file=None), bucket)
        service = FileService(db, oss)
        app.dependency_overrides[get_file_service] = lambda: service
        app.dependency_overrides[get_db] = lambda: db
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
        try:
            with TestClient(app) as client:
                yield client, bucket, db
        finally:
            app.dependency_overrides.clear()
    engine.dispose()


def sign(client, **changes):
    return client.post(
        "/api/v1/files/upload-signature",
        json={
            "filename": "照片.jpg",
            "content_type": "image/jpeg",
            "category": "image",
            "file_size": 123,
            **changes,
        },
    )


def complete(client, key, **changes):
    return client.post(
        "/api/v1/files/upload-complete",
        json={
            "object_key": key,
            "original_filename": "照片.jpg",
            "content_type": "image/jpeg",
            "file_size": 123,
            **changes,
        },
    )


def test_full_lifecycle_and_repeated_confirmation_delete(api):
    client, bucket, db = api
    signature = sign(client)
    assert signature.status_code == 200
    assert signature.headers["cache-control"] == "no-store"
    data = signature.json()["data"]
    assert data["object_key"].startswith("flutter/image/1/")
    assert "照片" not in data["object_key"]
    assert data["headers"]["Content-Length"] == "123"
    assert data["headers"]["x-oss-forbid-overwrite"] == "true"
    assert client.get("/api/v1/files").json()["data"] == []
    response = complete(client, data["object_key"])
    assert response.status_code == 200
    record = response.json()["data"]
    assert complete(client, data["object_key"]).json()["data"]["id"] == record["id"]
    assert len(list(db.scalars(select(FileRecord)))) == 1
    file_id = record["id"]
    assert client.get(f"/api/v1/files/{file_id}").status_code == 200
    assert client.get(f"/api/v1/files/{file_id}/download-url").json()["data"]["expire"] == 900
    assert len(client.get("/api/v1/files").json()["data"]) == 1
    for _ in range(2):
        assert client.delete(f"/api/v1/files/{file_id}").json() == {
            "code": 0,
            "message": "success",
            "data": None,
        }
    bucket.delete_object.assert_called_once()
    assert client.get(f"/api/v1/files/{file_id}").status_code == 404
    assert complete(client, data["object_key"]).status_code == 404
    assert client.get("/api/v1/files").json()["data"] == []
    assert db.get(FileRecord, file_id).deleted_at is not None


@pytest.mark.parametrize(
    "changes,status",
    [
        ({"category": "../"}, 400),
        ({"filename": "run.exe"}, 400),
        ({"filename": "../test.jpg"}, 400),
        ({"filename": "a\\b.jpg"}, 400),
        ({"filename": "a\r\nb.jpg"}, 400),
        ({"content_type": "text/html"}, 400),
        ({"file_size": 21 * 1024**2}, 413),
        ({"file_size": 0}, 400),
    ],
)
def test_reject_invalid_upload(api, changes, status):
    client, bucket, _ = api
    assert sign(client, **changes).status_code == status
    bucket.sign_url.assert_not_called()


def test_not_logged_in(api):
    client, _, _ = api
    del app.dependency_overrides[get_current_user]
    assert sign(client).status_code == 401


def test_confirm_missing_mismatched_and_unknown_objects(api):
    client, bucket, _ = api
    key = sign(client).json()["data"]["object_key"]
    bucket.object_exists.return_value = False
    assert complete(client, key).status_code == 404
    bucket.object_exists.return_value = True
    bucket.head_object.return_value.content_length = 900
    assert complete(client, key).status_code == 400
    assert complete(client, key, content_type="text/plain").status_code == 400
    assert complete(client, "flutter/image/1/20260908/not-issued.jpg").status_code == 404
    assert complete(client, "flutter/image/1/../not-issued.jpg").status_code == 400


def test_owner_isolation(api):
    client, bucket, _ = api
    key = sign(client).json()["data"]["object_key"]
    file_id = complete(client, key).json()["data"]["id"]
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=2)
    assert complete(client, key).status_code == 403
    assert client.get(f"/api/v1/files/{file_id}").status_code == 403
    assert client.get(f"/api/v1/files/{file_id}/download-url").status_code == 403
    assert client.delete(f"/api/v1/files/{file_id}").status_code == 403
    assert client.get("/api/v1/files").json()["data"] == []
    bucket.delete_object.assert_not_called()


def test_delete_failure_does_not_soft_delete_or_leak_signature(api):
    client, bucket, db = api
    key = sign(client).json()["data"]["object_key"]
    file_id = complete(client, key).json()["data"]["id"]
    bucket.delete_object.side_effect = oss2.exceptions.RequestError("Signature=secret")
    response = client.delete(f"/api/v1/files/{file_id}")
    assert response.status_code == 502
    assert "secret" not in response.text
    assert db.get(FileRecord, file_id).status == "active"


def test_file_used_by_post_cannot_be_deleted(api):
    client, bucket, db = api
    key = sign(client).json()["data"]["object_key"]
    file_id = complete(client, key).json()["data"]["id"]
    post = FeedPost(
        author_id=1,
        body="关联文件",
        media_kind="image",
        likes_count=0,
        comments_count=0,
        shares_count=0,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db.add(post)
    db.flush()
    db.add(
        FeedPostMedia(
            post_id=post.id,
            file_id=file_id,
            media_type="image",
            sort_order=0,
            created_at=datetime.now(timezone.utc),
        )
    )
    db.commit()
    response = client.delete(f"/api/v1/files/{file_id}")
    assert response.status_code == 409
    assert db.get(FileRecord, file_id).status == "active"
    bucket.delete_object.assert_not_called()


def test_file_used_by_direct_message_cannot_be_deleted(api):
    client, bucket, db = api
    key = sign(client).json()["data"]["object_key"]
    file_id = complete(client, key).json()["data"]["id"]
    message = DirectMessage(
        sender_id=1,
        recipient_id=2,
        body="图片",
        is_read=False,
        created_at=datetime.now(timezone.utc),
    )
    db.add(message)
    db.flush()
    db.add(
        DirectMessageMedia(
            message_id=message.id,
            file_id=file_id,
            media_type="image",
            sort_order=0,
            created_at=datetime.now(timezone.utc),
        )
    )
    db.commit()
    response = client.delete(f"/api/v1/files/{file_id}")
    assert response.status_code == 409
    assert db.get(FileRecord, file_id).status == "active"
    bucket.delete_object.assert_not_called()


def test_real_sdk_signature_without_network():
    config = Settings(
        _env_file=None, oss_access_key_id="test-id", oss_access_key_secret="test-secret"
    )
    service = OSSService(config)
    result = service.generate_upload_signature(
        "flutter/image/1/20260908/test.jpg", "image/jpeg", 123
    )
    query = parse_qs(urlsplit(result["upload_url"]).query)
    assert query["x-oss-expires"] == ["900"]
    assert query["x-oss-additional-headers"] == ["content-length"]
    assert "test-secret" not in result["upload_url"]
    assert "x-oss-signature" in query
    download = service.generate_download_url(result["object_key"], "照片.jpg", True)
    assert "attachment" in parse_qs(urlsplit(download).query)["response-content-disposition"][0]


def test_missing_configuration_and_unsafe_directory():
    service = OSSService(Settings(_env_file=None, oss_access_key_id="", oss_access_key_secret=""))
    with pytest.raises(AppException, match="OSS_ACCESS_KEY_ID"):
        service.check_configuration()
    service.config.oss_source_dir = "../private"
    with pytest.raises(AppException, match="目录配置非法"):
        service.build_object_key(1, "source", "photo.jpg")
