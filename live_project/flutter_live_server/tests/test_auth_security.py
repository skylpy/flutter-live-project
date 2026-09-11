from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import jwt
import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_auth_service, get_current_user, get_optional_current_user
from app.core.config import settings
from app.core.exceptions import AppException
from app.core.security import create_access_token, hash_password
from app.main import app
from app.models.user import User
from app.schemas.auth import UserRegisterRequest
from app.services.auth_service import AuthService


class FakeUserRepository:
    def __init__(self, users: list[User] | None = None) -> None:
        self.users = {user.username: user for user in users or []}
        self.next_id = max((user.id for user in self.users.values()), default=0) + 1

    def get_by_username(self, username: str) -> User | None:
        return self.users.get(username)

    def get_by_id(self, user_id: int) -> User | None:
        return next((user for user in self.users.values() if user.id == user_id), None)

    def create(self, user: User) -> User:
        if user.is_active is None:
            user.is_active = True
        user.id = self.next_id
        self.next_id += 1
        self.users[user.username] = user
        return user


def make_user(
    user_id: int = 1,
    username: str = "kevin",
    password: str = "secret123",
    *,
    active: bool = True,
) -> User:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return User(
        id=user_id,
        username=username,
        password_hash=hash_password(password),
        display_name="Kevin",
        is_active=active,
        created_at=now,
        updated_at=now,
    )


def test_auth_service_register_login_and_disabled_user_paths() -> None:
    repository = FakeUserRepository()
    service = AuthService(repository)

    session = service.register(
        UserRegisterRequest(username="new_user", password="secret123", displayName="新用户")
    )
    assert session.user.username == "new_user"
    assert session.user.display_name == "新用户"
    assert repository.users["new_user"].password_hash != "secret123"

    with pytest.raises(AppException) as duplicate:
        service.register(UserRegisterRequest(username="new_user", password="secret123"))
    assert (duplicate.value.status_code, duplicate.value.code) == (409, 40901)

    logged_in = service.login("new_user", "secret123")
    assert logged_in.user.id == session.user.id
    assert service.get_user(session.user.id).username == "new_user"

    with pytest.raises(AppException) as wrong_password:
        service.login("new_user", "wrong-password")
    assert (wrong_password.value.status_code, wrong_password.value.code) == (401, 40101)

    disabled = make_user(user_id=2, username="disabled", active=False)
    repository.users[disabled.username] = disabled
    with pytest.raises(AppException) as disabled_error:
        service.login("disabled", "secret123")
    assert (disabled_error.value.status_code, disabled_error.value.code) == (401, 40101)


@pytest.mark.parametrize(
    "payload",
    [
        {"username": "ab", "password": "secret123"},
        {"username": "bad-name", "password": "secret123"},
        {"username": "valid_name", "password": "short"},
        {"username": "valid_name", "password": "secret123", "displayName": ""},
    ],
)
def test_auth_request_schema_rejects_parameter_boundaries(payload: dict[str, str]) -> None:
    with pytest.raises(ValueError):
        UserRegisterRequest.model_validate(payload)


def test_auth_api_serializes_session_and_never_exposes_password_hash() -> None:
    user = make_user()
    service = AuthService(FakeUserRepository([user]))
    app.dependency_overrides[get_auth_service] = lambda: service
    try:
        with TestClient(app) as client:
            response = client.post(
                "/api/v1/auth/login",
                json={"username": "kevin", "password": "secret123"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["tokenType"] == "bearer"
    assert payload["user"] == {"id": 1, "username": "kevin", "displayName": "Kevin"}
    assert "password_hash" not in response.text


def test_current_user_rejects_missing_invalid_expired_and_disabled_tokens() -> None:
    user = make_user()
    repository = FakeUserRepository([user])

    with pytest.raises(AppException) as missing:
        get_current_user(credentials=None, db=SimpleNamespace())
    assert missing.value.status_code == 401

    from fastapi.security import HTTPAuthorizationCredentials

    invalid = HTTPAuthorizationCredentials(scheme="Bearer", credentials="not-a-jwt")
    with pytest.raises(AppException) as invalid_error:
        get_current_user(credentials=invalid, db=SimpleNamespace())
    assert invalid_error.value.code == 40100

    expired_token = jwt.encode(
        {
            "sub": "1",
            "username": "kevin",
            "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    expired = HTTPAuthorizationCredentials(scheme="Bearer", credentials=expired_token)
    with pytest.raises(AppException) as expired_error:
        get_current_user(credentials=expired, db=SimpleNamespace())
    assert expired_error.value.code == 40100

    class Database:
        def get(self, model, user_id: int) -> User | None:
            return repository.get_by_id(user_id)

    # The dependency constructs UserRepository(db), so a minimal Session-like object
    # is enough to exercise the authenticated and inactive-user branches.
    valid = HTTPAuthorizationCredentials(
        scheme="Bearer", credentials=create_access_token(user.id, user.username)
    )
    assert get_current_user(credentials=valid, db=Database()).id == 1
    user.is_active = False
    with pytest.raises(AppException) as inactive:
        get_current_user(credentials=valid, db=Database())
    assert inactive.value.code == 40102
    assert get_optional_current_user(credentials=None, db=Database()) is None
