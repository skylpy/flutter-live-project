"""钱包、礼物与直播间礼物统计的持久化模型。

余额只是当前快照；所有可见余额变化都必须同时写入 ``WalletLedger``，
以便后续接入 App Store / Google Play 回执、退款和人工补单时能够审计。
"""

from datetime import datetime
from typing import Optional

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


_ID = BigInteger().with_variant(Integer(), "sqlite")


class Wallet(Base):
    """一个用户一份钱包快照。

    ``available_balance`` 是可送礼的测试金币，``income_balance`` 是主播收到的
    礼物收益展示值。本轮不提供提现，因此收益不会转换成可消费金币。
    """

    __tablename__ = "wallets"
    __table_args__ = (UniqueConstraint("user_id", name="uq_wallets_user_id"),)

    id: Mapped[int] = mapped_column(_ID, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    available_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    income_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class WalletLedger(Base):
    """钱包不可变流水。

    ``amount`` 为带正负号的整数。``balance_after`` 保留写入后的余额快照，
    因而不依赖未来余额表的状态也能完成账务回溯。
    """

    __tablename__ = "wallet_ledgers"
    __table_args__ = (
        UniqueConstraint("idempotency_key", name="uq_wallet_ledgers_idempotency_key"),
    )

    id: Mapped[int] = mapped_column(_ID, primary_key=True, autoincrement=True)
    wallet_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("wallets.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # spendable: 可消费金币；income: 主播礼物收益。
    balance_type: Mapped[str] = mapped_column(String(20), nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    business_type: Mapped[str] = mapped_column(String(40), nullable=False)
    reference_type: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    reference_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True, index=True)
    idempotency_key: Mapped[str] = mapped_column(String(160), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class GiftCatalog(Base):
    """可运营的礼物目录。礼物价格只由服务端读取，客户端不得提交价格。"""

    __tablename__ = "gift_catalog"

    id: Mapped[int] = mapped_column(_ID, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(60), nullable=False)
    icon: Mapped[str] = mapped_column(String(32), nullable=False)
    animation_key: Mapped[str] = mapped_column(String(80), nullable=False)
    price: Mapped[int] = mapped_column(Integer, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class GiftTransaction(Base):
    """一笔已成功的送礼订单；它与两条钱包流水共同构成完整审计链。"""

    __tablename__ = "gift_transactions"
    __table_args__ = (
        UniqueConstraint("idempotency_key", name="uq_gift_transactions_idempotency_key"),
    )

    id: Mapped[int] = mapped_column(_ID, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    anchor_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    gift_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gift_catalog.id", ondelete="RESTRICT"), nullable=False
    )
    # 保存展示快照，礼物改名/下架后历史记录仍能正确展示。
    gift_name: Mapped[str] = mapped_column(String(60), nullable=False)
    gift_icon: Mapped[str] = mapped_column(String(32), nullable=False)
    animation_key: Mapped[str] = mapped_column(String(80), nullable=False)
    unit_price: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    total_amount: Mapped[int] = mapped_column(Integer, nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(120), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class LiveRoomGiftStat(Base):
    """按房间和送礼用户聚合，用于实时贡献榜而不扫描全量订单。"""

    __tablename__ = "live_room_gift_stats"
    __table_args__ = (
        UniqueConstraint("room_id", "user_id", name="uq_live_room_gift_stats_room_user"),
    )

    id: Mapped[int] = mapped_column(_ID, primary_key=True, autoincrement=True)
    room_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("live_rooms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    total_amount: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    gift_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
