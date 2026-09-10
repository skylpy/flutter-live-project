"""钱包写入与礼物统计的数据访问层。"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import desc, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import AppException, NotFoundException
from app.models.live_room import LiveRoom
from app.models.user import User
from app.models.wallet import GiftCatalog, GiftTransaction, LiveRoomGiftStat, Wallet, WalletLedger


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class WalletRepository:
    """所有余额变化都通过这里完成，禁止调用方直接修改 Wallet。"""

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_or_create_wallet(self, user_id: int) -> Wallet:
        wallet = self._wallet_for_user(user_id, lock=False)
        if wallet is None:
            wallet = Wallet(
                user_id=user_id,
                available_balance=0,
                income_balance=0,
                updated_at=_utcnow(),
            )
            self.db.add(wallet)
            self.db.commit()
            self.db.refresh(wallet)
        return wallet

    def list_ledgers(self, user_id: int, limit: int) -> list[WalletLedger]:
        return list(
            self.db.scalars(
                select(WalletLedger)
                .where(WalletLedger.user_id == user_id)
                .order_by(desc(WalletLedger.created_at), desc(WalletLedger.id))
                .limit(limit)
            ).all()
        )

    def grant_test_coins(self, user_id: int, amount: int, idempotency_key: str) -> Wallet:
        """写入一笔测试金币流水；相同幂等键只生效一次。"""
        try:
            existing = self.db.scalar(
                select(WalletLedger).where(WalletLedger.idempotency_key == idempotency_key)
            )
            if existing is not None:
                return self.get_or_create_wallet(user_id)
            wallet = self._locked_wallet(user_id)
            wallet.available_balance += amount
            wallet.updated_at = _utcnow()
            self.db.add(
                WalletLedger(
                    wallet_id=wallet.id,
                    user_id=user_id,
                    balance_type="spendable",
                    amount=amount,
                    balance_after=wallet.available_balance,
                    business_type="test_grant",
                    reference_type="test_grant",
                    reference_id=None,
                    idempotency_key=idempotency_key,
                    created_at=_utcnow(),
                )
            )
            self.db.commit()
            self.db.refresh(wallet)
            return wallet
        except IntegrityError:
            # 双击或弱网重试在并发到达时由唯一约束兜底；重新读取结果即可。
            self.db.rollback()
            return self.get_or_create_wallet(user_id)
        except Exception:
            self.db.rollback()
            raise

    def list_gifts(self) -> list[GiftCatalog]:
        return list(
            self.db.scalars(
                select(GiftCatalog)
                .where(GiftCatalog.is_active.is_(True))
                .order_by(GiftCatalog.sort_order.asc(), GiftCatalog.id.asc())
            ).all()
        )

    def send_gift(
        self,
        *,
        room_id: int,
        sender: User,
        gift_id: int,
        quantity: int,
        idempotency_key: str,
    ) -> tuple[GiftTransaction, Wallet, Wallet, bool]:
        """原子地完成扣款、收益、双流水、订单和榜单聚合。

        返回末尾标志表示本次是否真正创建新订单；WebSocket 只应在新订单后
        广播，幂等重放不能重复播放动画。
        """
        try:
            existing = self.db.scalar(
                select(GiftTransaction).where(GiftTransaction.idempotency_key == idempotency_key)
            )
            if existing is not None:
                if existing.sender_id != sender.id:
                    raise AppException("幂等请求与当前用户不匹配", 40912, 409)
                return (
                    existing,
                    self.get_or_create_wallet(existing.sender_id),
                    self.get_or_create_wallet(existing.anchor_id),
                    False,
                )

            room = self.db.get(LiveRoom, room_id)
            if room is None:
                raise NotFoundException("直播间不存在", 40401)
            if room.status != "living" or room.anchor_user_id is None:
                raise AppException("当前直播间未开播或已结束", 40910, 409)
            if room.anchor_user_id == sender.id:
                raise AppException("主播不能向自己的直播间送礼", 40070, 400)

            gift = self.db.get(GiftCatalog, gift_id)
            if gift is None or not gift.is_active:
                raise NotFoundException("礼物不存在或已下架", 40470)

            sender_wallet = self._locked_wallet(sender.id)
            anchor_wallet = self._locked_wallet(room.anchor_user_id)
            total_amount = gift.price * quantity
            if sender_wallet.available_balance < total_amount:
                raise AppException("金币余额不足，请先领取测试金币", 40911, 409)

            now = _utcnow()
            sender_wallet.available_balance -= total_amount
            sender_wallet.updated_at = now
            anchor_wallet.income_balance += total_amount
            anchor_wallet.updated_at = now
            transaction = GiftTransaction(
                room_id=room.id,
                sender_id=sender.id,
                anchor_id=room.anchor_user_id,
                gift_id=gift.id,
                gift_name=gift.name,
                gift_icon=gift.icon,
                animation_key=gift.animation_key,
                unit_price=gift.price,
                quantity=quantity,
                total_amount=total_amount,
                idempotency_key=idempotency_key,
                created_at=now,
            )
            self.db.add(transaction)
            self.db.flush()
            self.db.add_all(
                [
                    WalletLedger(
                        wallet_id=sender_wallet.id,
                        user_id=sender.id,
                        balance_type="spendable",
                        amount=-total_amount,
                        balance_after=sender_wallet.available_balance,
                        business_type="gift_spend",
                        reference_type="gift_transaction",
                        reference_id=transaction.id,
                        idempotency_key=f"{idempotency_key}:spend",
                        created_at=now,
                    ),
                    WalletLedger(
                        wallet_id=anchor_wallet.id,
                        user_id=room.anchor_user_id,
                        balance_type="income",
                        amount=total_amount,
                        balance_after=anchor_wallet.income_balance,
                        business_type="gift_income",
                        reference_type="gift_transaction",
                        reference_id=transaction.id,
                        idempotency_key=f"{idempotency_key}:income",
                        created_at=now,
                    ),
                ]
            )
            statistic = self.db.scalar(
                select(LiveRoomGiftStat)
                .where(
                    LiveRoomGiftStat.room_id == room.id,
                    LiveRoomGiftStat.user_id == sender.id,
                )
                .with_for_update()
            )
            if statistic is None:
                statistic = LiveRoomGiftStat(
                    room_id=room.id,
                    user_id=sender.id,
                    total_amount=0,
                    gift_count=0,
                    updated_at=now,
                )
                self.db.add(statistic)
            statistic.total_amount += total_amount
            statistic.gift_count += quantity
            statistic.updated_at = now
            self.db.commit()
            self.db.refresh(transaction)
            self.db.refresh(sender_wallet)
            self.db.refresh(anchor_wallet)
            return transaction, sender_wallet, anchor_wallet, True
        except IntegrityError:
            self.db.rollback()
            existing = self.db.scalar(
                select(GiftTransaction).where(GiftTransaction.idempotency_key == idempotency_key)
            )
            if existing is None:
                raise
            if existing.sender_id != sender.id:
                raise AppException("幂等请求与当前用户不匹配", 40912, 409)
            return (
                existing,
                self.get_or_create_wallet(existing.sender_id),
                self.get_or_create_wallet(existing.anchor_id),
                False,
            )
        except Exception:
            self.db.rollback()
            raise

    def room_gift_records(self, room_id: int, limit: int) -> list[tuple[GiftTransaction, User]]:
        return list(
            self.db.execute(
                select(GiftTransaction, User)
                .join(User, User.id == GiftTransaction.sender_id)
                .where(GiftTransaction.room_id == room_id)
                .order_by(desc(GiftTransaction.created_at), desc(GiftTransaction.id))
                .limit(limit)
            ).all()
        )

    def room_gift_stats(self, room_id: int) -> tuple[LiveRoom, int, int, list[tuple]]:
        room = self.db.get(LiveRoom, room_id)
        if room is None or room.anchor_user_id is None:
            raise NotFoundException("直播间不存在", 40401)
        totals = self.db.execute(
            select(
                func.coalesce(func.sum(GiftTransaction.total_amount), 0),
                func.coalesce(func.sum(GiftTransaction.quantity), 0),
            ).where(GiftTransaction.room_id == room_id)
        ).one()
        rankings = self.db.execute(
            select(
                LiveRoomGiftStat.user_id,
                User.display_name,
                LiveRoomGiftStat.total_amount,
                LiveRoomGiftStat.gift_count,
            )
            .join(User, User.id == LiveRoomGiftStat.user_id)
            .where(LiveRoomGiftStat.room_id == room_id)
            .order_by(desc(LiveRoomGiftStat.total_amount), desc(LiveRoomGiftStat.updated_at))
            .limit(10)
        ).all()
        return room, int(totals[0] or 0), int(totals[1] or 0), list(rankings)

    def _wallet_for_user(self, user_id: int, *, lock: bool) -> Optional[Wallet]:
        statement = select(Wallet).where(Wallet.user_id == user_id)
        if lock:
            statement = statement.with_for_update()
        return self.db.scalar(statement)

    def _locked_wallet(self, user_id: int) -> Wallet:
        wallet = self._wallet_for_user(user_id, lock=True)
        if wallet is None:
            wallet = Wallet(
                user_id=user_id,
                available_balance=0,
                income_balance=0,
                updated_at=_utcnow(),
            )
            self.db.add(wallet)
            self.db.flush()
        return wallet
