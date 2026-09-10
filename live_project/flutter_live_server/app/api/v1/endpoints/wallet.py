"""钱包、礼物目录和直播间送礼接口。"""

from fastapi import APIRouter, Depends, Path, Query

from app.api.deps import get_current_user, get_wallet_service
from app.models.user import User
from app.schemas.common import ApiResponse, success
from app.schemas.wallet import (
    GiftRecordResponse,
    GiftResponse,
    GiftTransactionResponse,
    RoomGiftStatsResponse,
    SendGiftRequest,
    TestGrantRequest,
    WalletLedgerResponse,
    WalletResponse,
)
from app.services.realtime_service import event_time, room_realtime_hub
from app.services.wallet_service import WalletService

router = APIRouter(tags=["wallet"])


@router.get("/wallet", response_model=ApiResponse[WalletResponse])
def get_wallet(
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[WalletResponse]:
    return success(service.wallet(user))


@router.get("/wallet/ledger", response_model=ApiResponse[list[WalletLedgerResponse]])
def get_wallet_ledger(
    limit: int = Query(default=50, ge=1, le=100),
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[list[WalletLedgerResponse]]:
    return success(service.ledger(user, limit))


@router.post("/wallet/test-grants", response_model=ApiResponse[WalletResponse])
def grant_test_coins(
    payload: TestGrantRequest,
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[WalletResponse]:
    """仅本地开发/测试期领取测试金币，生产环境会返回 403。"""
    return success(
        service.grant_test_coins(user, payload.amount, payload.idempotency_key),
        message="测试金币已到账",
    )


@router.get("/gifts", response_model=ApiResponse[list[GiftResponse]])
def list_gifts(
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[list[GiftResponse]]:
    return success(service.gifts())


@router.post(
    "/live/rooms/{room_id}/gifts",
    response_model=ApiResponse[GiftTransactionResponse],
)
async def send_gift(
    payload: SendGiftRequest,
    room_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[GiftTransactionResponse]:
    """送礼先落库，再广播给房间中的主播和观众。"""
    transaction = service.send_gift(
        room_id=room_id,
        sender=user,
        gift_id=payload.gift_id,
        quantity=payload.quantity,
        idempotency_key=payload.idempotency_key,
    )
    if not transaction.replayed:
        await room_realtime_hub.publish(
            room_id,
            {
                "type": "gift",
                "event": "sent",
                "roomId": room_id,
                "userId": user.id,
                "userName": user.display_name,
                "message": f"{user.display_name} 送出了 {transaction.gift_name} × {transaction.quantity}",
                "gift": transaction.model_dump(by_alias=True),
                "sentAt": event_time(),
            },
        )
    return success(transaction, message="礼物已送出")


@router.get(
    "/live/rooms/{room_id}/gift-records",
    response_model=ApiResponse[list[GiftRecordResponse]],
)
def room_gift_records(
    room_id: int = Path(..., ge=1),
    limit: int = Query(default=50, ge=1, le=100),
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[list[GiftRecordResponse]]:
    # 用户身份是为了与房间接口保持一致，也为后续只向房间参与者展示记录留入口。
    del user
    return success(service.records(room_id, limit))


@router.get(
    "/live/rooms/{room_id}/gift-stats",
    response_model=ApiResponse[RoomGiftStatsResponse],
)
def room_gift_stats(
    room_id: int = Path(..., ge=1),
    user: User = Depends(get_current_user),
    service: WalletService = Depends(get_wallet_service),
) -> ApiResponse[RoomGiftStatsResponse]:
    del user
    return success(service.stats(room_id))
