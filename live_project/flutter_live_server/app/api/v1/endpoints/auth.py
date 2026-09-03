from fastapi import APIRouter, Depends

from app.api.deps import get_auth_service, get_current_user
from app.models.user import User
from app.schemas.auth import (
    AuthSessionResponse,
    UserLoginRequest,
    UserRegisterRequest,
    UserResponse,
)
from app.schemas.common import ApiResponse, success
from app.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=ApiResponse[AuthSessionResponse], status_code=201)
def register(
    request: UserRegisterRequest,
    service: AuthService = Depends(get_auth_service),
) -> ApiResponse[AuthSessionResponse]:
    return success(service.register(request))


@router.post("/login", response_model=ApiResponse[AuthSessionResponse])
def login(
    request: UserLoginRequest,
    service: AuthService = Depends(get_auth_service),
) -> ApiResponse[AuthSessionResponse]:
    return success(service.login(request.username, request.password))


@router.get("/me", response_model=ApiResponse[UserResponse])
def me(user: User = Depends(get_current_user)) -> ApiResponse[UserResponse]:
    return success(user)
