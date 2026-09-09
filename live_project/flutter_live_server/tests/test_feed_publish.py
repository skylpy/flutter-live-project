from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.deps import get_current_user
from app.api.deps_social import get_social_service
from app.core.database import get_db
from app.main import app
from app.models.base import Base
from app.models.file import FileRecord
from app.models.social import (
    DirectMessage,
    DirectMessageMedia,
    FeedComment,
    FeedLike,
    FeedPost,
    FeedPostMedia,
    Follow,
)
from app.models.user import User
from app.repositories.social_repository import SocialRepository
from app.services.social_service import SocialService


class FakeOss:
    def __init__(self) -> None:
        self.deleted_keys: list[str] = []

    def generate_download_url(self, object_key: str, *args, **kwargs) -> str:
        return f"https://media.example.invalid/{object_key}"

    def delete_object(self, object_key: str) -> None:
        self.deleted_keys.append(object_key)


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
            FeedComment.__table__,
            FeedLike.__table__,
            Follow.__table__,
        ],
    )
    now = datetime.now(timezone.utc)
    with Session(engine) as db:
        db.add_all(
            [
                User(
                    id=1,
                    username="owner",
                    password_hash="unused",
                    display_name="发布者",
                    is_active=True,
                    created_at=now,
                    updated_at=now,
                ),
                User(
                    id=2,
                    username="other",
                    password_hash="unused",
                    display_name="其他用户",
                    is_active=True,
                    created_at=now,
                    updated_at=now,
                ),
                FileRecord(
                    id=11,
                    user_id=1,
                    object_key="flutter/image/1/20260908/photo.jpg",
                    original_filename="photo.jpg",
                    content_type="image/jpeg",
                    file_size=12,
                    category="image",
                    status="active",
                    created_at=now,
                    updated_at=now,
                ),
                FileRecord(
                    id=12,
                    user_id=2,
                    object_key="flutter/image/2/20260908/other.jpg",
                    original_filename="other.jpg",
                    content_type="image/jpeg",
                    file_size=12,
                    category="image",
                    status="active",
                    created_at=now,
                    updated_at=now,
                ),
                FileRecord(
                    id=13,
                    user_id=1,
                    object_key="flutter/video/1/20260908/movie.mp4",
                    original_filename="movie.mp4",
                    content_type="video/mp4",
                    file_size=12,
                    category="video",
                    status="active",
                    created_at=now,
                    updated_at=now,
                ),
            ]
        )
        db.commit()
        oss = FakeOss()
        service = SocialService(SocialRepository(db), oss)
        app.dependency_overrides[get_db] = lambda: db
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
            id=1, display_name="发布者"
        )
        app.dependency_overrides[get_social_service] = lambda: service
        try:
            with TestClient(app) as client:
                yield client, db, oss
        finally:
            app.dependency_overrides.clear()
    engine.dispose()


def test_publish_post_with_uploaded_image_and_refresh_feed(api):
    client, db, _ = api
    response = client.post("/api/v1/feed/posts", json={"body": "我的第一条动态", "file_ids": [11]})
    assert response.status_code == 201
    published = response.json()["data"]
    assert published["body"] == "我的第一条动态"
    assert published["mediaKind"] == "image"
    assert published["media"] == [
        {
            "fileId": 11,
            "mediaType": "image",
            "url": "https://media.example.invalid/flutter/image/1/20260908/photo.jpg",
        }
    ]
    assert db.get(FeedPost, published["id"]).author_id == 1
    assert client.get("/api/v1/feed/posts?tab=最新").json()["data"][0]["id"] == published["id"]


@pytest.mark.parametrize(
    ("payload", "status"),
    [
        ({"body": "   ", "file_ids": []}, 400),
        ({"body": "重复", "file_ids": [11, 11]}, 400),
        ({"body": "混用", "file_ids": [11, 13]}, 400),
        ({"body": "越权", "file_ids": [12]}, 403),
    ],
)
def test_publish_rejects_invalid_or_unowned_media(api, payload, status):
    client, _, _ = api
    assert client.post("/api/v1/feed/posts", json=payload).status_code == status


def test_comments_preview_detail_and_delete_own_post(api):
    client, db, oss = api
    post = client.post("/api/v1/feed/posts", json={"body": "可评论动态", "file_ids": [11]})
    post_id = post.json()["data"]["id"]

    for index in range(4):
        response = client.post(
            f"/api/v1/feed/posts/{post_id}/comments", json={"body": f"评论 {index}"}
        )
        assert response.status_code == 201

    feed_post = client.get("/api/v1/feed/posts?tab=推荐").json()["data"][0]
    assert feed_post["comments"] == 4
    assert [comment["body"] for comment in feed_post["commentsPreview"]] == [
        "评论 1",
        "评论 2",
        "评论 3",
    ]
    assert feed_post["canDelete"] is True

    comments = client.get(f"/api/v1/feed/posts/{post_id}/comments").json()["data"]
    assert [comment["body"] for comment in comments] == [
        "评论 0",
        "评论 1",
        "评论 2",
        "评论 3",
    ]
    assert client.delete(f"/api/v1/feed/posts/{post_id}").status_code == 200
    assert db.get(FeedPost, post_id) is None
    assert db.get(FileRecord, 11).status == "deleted"
    assert oss.deleted_keys == ["flutter/image/1/20260908/photo.jpg"]
    assert client.get(f"/api/v1/feed/posts/{post_id}").status_code == 404


def test_public_profile_follow_and_delete_permission(api):
    client, _, _ = api
    created = client.post("/api/v1/feed/posts", json={"body": "发布者动态", "file_ids": []})
    post_id = created.json()["data"]["id"]

    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=2, display_name="其他用户"
    )
    profile = client.get("/api/v1/feed/users/1")
    assert profile.status_code == 200
    assert profile.json()["data"]["postCount"] == 1
    assert profile.json()["data"]["posts"][0]["canDelete"] is False
    follow_response = client.post("/api/v1/users/1/follow")
    assert follow_response.status_code == 200, follow_response.json()
    assert follow_response.json()["data"] == {
        "active": True,
        "count": 1,
    }
    assert client.delete(f"/api/v1/feed/posts/{post_id}").status_code == 403

    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=1, display_name="发布者"
    )
    assert (
        client.post(f"/api/v1/feed/posts/{post_id}/comments", json={"body": "   "}).status_code
        == 400
    )


def test_direct_message_thread_media_unread_and_owner_isolation(api):
    client, _, _ = api
    response = client.post(
        "/api/v1/messages",
        json={"recipient_id": 2, "body": "给你看张照片", "file_ids": [11]},
    )
    assert response.status_code == 201
    sent = response.json()["data"]
    assert sent["isMine"] is True
    assert sent["media"] == [
        {
            "fileId": 11,
            "mediaType": "image",
            "url": "https://media.example.invalid/flutter/image/1/20260908/photo.jpg",
        }
    ]
    assert (
        client.post(
            "/api/v1/messages", json={"recipient_id": 2, "body": "", "file_ids": [12]}
        ).status_code
        == 403
    )

    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
        id=2, display_name="其他用户"
    )
    thread = client.get("/api/v1/messages/conversations/1")
    assert thread.status_code == 200
    assert thread.json()["data"][0]["id"] == sent["id"]
    assert thread.json()["data"][0]["isMine"] is False
    conversation = client.get("/api/v1/messages/conversations").json()["data"]
    assert conversation == [
        {
            "userId": 1,
            "userName": "发布者",
            "preview": "给你看张照片",
            "timeLabel": "刚刚",
            "unread": 0,
        }
    ]
