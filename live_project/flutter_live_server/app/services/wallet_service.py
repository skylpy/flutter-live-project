"""钱包与直播礼物的业务编排。"""

from __future__ import annotations

from app.core.config import settings
from app.core.exceptions import AppException
from app.models.user import User
from app.repositories.wallet_repository import WalletRepository
from app.schemas.wallet import (
    GiftRankResponse,
    GiftRecordResponse,
    GiftResponse,
    GiftTransactionResponse,
    RoomGiftStatsResponse,
    WalletResponse,
    ledger_response,
    transaction_time_label,
)


class WalletService:
    def __init__(self, repository: WalletRepository) -> None:
        self.repository = repository

    @property
    def is_test_mode(self) -> bool:
        return settings.app_env.lower() in {"development", "dev", "test"}

    def wallet(self, user: User) -> WalletResponse:
        return self._wallet_response(self.repository.get_or_create_wallet(user.id))

    def ledger(self, user: User, limit: int):
        return [
            ledger_response(item, self._ledger_title(item.business_type))
            for item in self.repository.list_ledgers(user.id, limit)
        ]

    def grant_test_coins(self, user: User, amount: int, idempotency_key: str) -> WalletResponse:
        if not self.is_test_mode:
            raise AppException("测试金币只在开发和测试环境开放", 40370, 403)
        return self._wallet_response(
            self.repository.grant_test_coins(user.id, amount, idempotency_key)
        )

    def gifts(self) -> list[GiftResponse]:
        return [GiftResponse.model_validate(item) for item in self.repository.list_gifts()]

    def send_gift(
        self,
        *,
        room_id: int,
        sender: User,
        gift_id: int,
        quantity: int,
        idempotency_key: str,
    ) -> GiftTransactionResponse:
        transaction, sender_wallet, anchor_wallet, is_new = self.repository.send_gift(
            room_id=room_id,
            sender=sender,
            gift_id=gift_id,
            quantity=quantity,
            idempotency_key=idempotency_key,
        )
        anchor_name = "主播"
        anchor = self.repository.db.get(User, transaction.anchor_id)
        if anchor is not None:
            anchor_name = anchor.display_name
        return GiftTransactionResponse(
            id=transaction.id,
            room_id=transaction.room_id,
            sender_id=transaction.sender_id,
            sender_name=sender.display_name,
            anchor_id=transaction.anchor_id,
            anchor_name=anchor_name,
            gift_id=transaction.gift_id,
            gift_name=transaction.gift_name,
            gift_icon=transaction.gift_icon,
            animation_key=transaction.animation_key,
            unit_price=transaction.unit_price,
            quantity=transaction.quantity,
            total_amount=transaction.total_amount,
            sender_balance=sender_wallet.available_balance,
            anchor_income=anchor_wallet.income_balance,
            time_label=transaction_time_label(transaction.created_at),
            replayed=not is_new,
        )

    def records(self, room_id: int, limit: int) -> list[GiftRecordResponse]:
        return [
            GiftRecordResponse(
                id=transaction.id,
                sender_id=sender.id,
                sender_name=sender.display_name,
                gift_name=transaction.gift_name,
                gift_icon=transaction.gift_icon,
                quantity=transaction.quantity,
                total_amount=transaction.total_amount,
                time_label=transaction_time_label(transaction.created_at),
            )
            for transaction, sender in self.repository.room_gift_records(room_id, limit)
        ]

    def stats(self, room_id: int) -> RoomGiftStatsResponse:
        room, total_revenue, total_gift_count, rankings = self.repository.room_gift_stats(room_id)
        return RoomGiftStatsResponse(
            room_id=room.id,
            anchor_id=room.anchor_user_id,
            total_revenue=total_revenue,
            total_gift_count=total_gift_count,
            top_supporters=[
                GiftRankResponse(
                    user_id=user_id,
                    user_name=user_name,
                    total_amount=amount,
                    gift_count=count,
                )
                for user_id, user_name, amount, count in rankings
            ],
        )

    def _wallet_response(self, wallet) -> WalletResponse:
        return WalletResponse(
            available_balance=wallet.available_balance,
            income_balance=wallet.income_balance,
            test_mode=self.is_test_mode,
        )

    @staticmethod
    def _ledger_title(business_type: str) -> str:
        return {
            "test_grant": "领取测试金币",
            "gift_spend": "直播间送礼",
            "gift_income": "收到直播礼物",
            "purchase_credit": "购买金币",
            "refund": "退款补回",
            "manual_adjustment": "运营补偿",
        }.get(business_type, "钱包变动")
