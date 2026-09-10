"""钱包与礼物 API 的输入、输出契约。"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.schemas.social import format_time_label


class WalletResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    available_balance: int = Field(serialization_alias="availableBalance")
    income_balance: int = Field(serialization_alias="incomeBalance")
    currency_name: str = Field(default="金币", serialization_alias="currencyName")
    income_name: str = Field(default="礼物收益", serialization_alias="incomeName")
    test_mode: bool = Field(serialization_alias="testMode")


class WalletLedgerResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: int
    balance_type: str = Field(serialization_alias="balanceType")
    amount: int
    balance_after: int = Field(serialization_alias="balanceAfter")
    business_type: str = Field(serialization_alias="businessType")
    reference_type: str = Field(serialization_alias="referenceType")
    reference_id: Optional[int] = Field(default=None, serialization_alias="referenceId")
    title: str
    time_label: str = Field(serialization_alias="timeLabel")


class TestGrantRequest(BaseModel):
    """仅开发/测试环境可用的测试金币发放请求。"""

    model_config = ConfigDict(populate_by_name=True)

    amount: int = Field(default=1000, ge=1, le=10_000)
    idempotency_key: str = Field(min_length=8, max_length=120)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_case(cls, value):
        """兼容 Flutter 的 camelCase 请求，而不触发 FastAPI 字段拆解警告。"""
        if isinstance(value, dict) and "idempotencyKey" in value:
            value = dict(value)
            value["idempotency_key"] = value["idempotencyKey"]
        return value


class GiftResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    name: str
    icon: str
    animation_key: str = Field(serialization_alias="animationKey")
    price: int


class SendGiftRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    gift_id: int = Field(ge=1)
    quantity: int = Field(default=1, ge=1, le=99)
    idempotency_key: str = Field(min_length=8, max_length=120)

    @model_validator(mode="before")
    @classmethod
    def accept_camel_case(cls, value):
        if isinstance(value, dict):
            value = dict(value)
            if "giftId" in value:
                value["gift_id"] = value["giftId"]
            if "idempotencyKey" in value:
                value["idempotency_key"] = value["idempotencyKey"]
        return value


class GiftTransactionResponse(BaseModel):
    """送礼成功后既可作为 REST 返回，也可作为 WebSocket gift 载荷。"""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    room_id: int = Field(serialization_alias="roomId")
    sender_id: int = Field(serialization_alias="senderId")
    sender_name: str = Field(serialization_alias="senderName")
    anchor_id: int = Field(serialization_alias="anchorId")
    anchor_name: str = Field(serialization_alias="anchorName")
    gift_id: int = Field(serialization_alias="giftId")
    gift_name: str = Field(serialization_alias="giftName")
    gift_icon: str = Field(serialization_alias="giftIcon")
    animation_key: str = Field(serialization_alias="animationKey")
    unit_price: int = Field(serialization_alias="unitPrice")
    quantity: int
    total_amount: int = Field(serialization_alias="totalAmount")
    sender_balance: int = Field(serialization_alias="senderBalance")
    anchor_income: int = Field(serialization_alias="anchorIncome")
    time_label: str = Field(serialization_alias="timeLabel")
    replayed: bool = False


class GiftRecordResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: int
    sender_id: int = Field(serialization_alias="senderId")
    sender_name: str = Field(serialization_alias="senderName")
    gift_name: str = Field(serialization_alias="giftName")
    gift_icon: str = Field(serialization_alias="giftIcon")
    quantity: int
    total_amount: int = Field(serialization_alias="totalAmount")
    time_label: str = Field(serialization_alias="timeLabel")


class GiftRankResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    user_id: int = Field(serialization_alias="userId")
    user_name: str = Field(serialization_alias="userName")
    total_amount: int = Field(serialization_alias="totalAmount")
    gift_count: int = Field(serialization_alias="giftCount")


class RoomGiftStatsResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    room_id: int = Field(serialization_alias="roomId")
    anchor_id: int = Field(serialization_alias="anchorId")
    total_revenue: int = Field(serialization_alias="totalRevenue")
    total_gift_count: int = Field(serialization_alias="totalGiftCount")
    top_supporters: list[GiftRankResponse] = Field(serialization_alias="topSupporters")


def ledger_response(ledger, title: str) -> WalletLedgerResponse:
    """集中完成流水 ORM -> API DTO 的时间格式转换。"""

    return WalletLedgerResponse(
        id=ledger.id,
        balance_type=ledger.balance_type,
        amount=ledger.amount,
        balance_after=ledger.balance_after,
        business_type=ledger.business_type,
        reference_type=ledger.reference_type,
        reference_id=ledger.reference_id,
        title=title,
        time_label=format_time_label(ledger.created_at),
    )


def transaction_time_label(value: datetime) -> str:
    return format_time_label(value)
