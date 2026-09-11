from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.deps import get_current_user, get_wallet_service
from app.main import app
from app.models.base import Base
from app.models.live_room import LiveRoom
from app.models.user import User
from app.models.wallet import GiftCatalog, GiftTransaction, LiveRoomGiftStat, Wallet, WalletLedger
from app.repositories.wallet_repository import WalletRepository
from app.services.wallet_service import WalletService


@pytest.fixture
def wallet_api():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            LiveRoom.__table__,
            Wallet.__table__,
            WalletLedger.__table__,
            GiftCatalog.__table__,
            GiftTransaction.__table__,
            LiveRoomGiftStat.__table__,
        ],
    )
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    with Session(engine) as db:
        sender = User(
            id=1,
            username="viewer",
            password_hash="unused",
            display_name="观众",
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        anchor = User(
            id=2,
            username="anchor",
            password_hash="unused",
            display_name="主播",
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        room = LiveRoom(
            id=11,
            title="礼物验收直播间",
            anchor_user_id=2,
            anchor_name="主播",
            anchor_avatar="",
            online_count=2,
            cover_url="",
            status="living",
            play_url="http://example.invalid/live.m3u8",
            push_url="rtmp://example.invalid/live",
            stream_name="room_gift_test",
            category="综合",
            created_at=now,
            updated_at=now,
        )
        gift = GiftCatalog(
            id=1,
            name="玫瑰",
            icon="🌹",
            animation_key="rose",
            price=66,
            sort_order=1,
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        db.add_all([sender, anchor, room, gift])
        db.commit()

        current = {"user": sender}
        service = WalletService(WalletRepository(db))
        app.dependency_overrides[get_current_user] = lambda: current["user"]
        app.dependency_overrides[get_wallet_service] = lambda: service
        try:
            with TestClient(app) as client:
                yield client, db, current
        finally:
            app.dependency_overrides.clear()
    engine.dispose()


def test_test_coin_wallet_gift_ledger_and_room_rank(wallet_api):
    client, db, current = wallet_api

    assert client.get("/api/v1/wallet").json()["data"]["availableBalance"] == 0
    grant = client.post(
        "/api/v1/wallet/test-grants",
        json={"amount": 1000, "idempotencyKey": "wallet-test-grant-001"},
    )
    assert grant.status_code == 200
    assert grant.json()["data"]["availableBalance"] == 1000

    sent = client.post(
        "/api/v1/live/rooms/11/gifts",
        json={"giftId": 1, "quantity": 2, "idempotencyKey": "gift-transaction-001"},
    )
    assert sent.status_code == 200, sent.json()
    receipt = sent.json()["data"]
    assert receipt["totalAmount"] == 132
    assert receipt["senderBalance"] == 868
    assert receipt["anchorIncome"] == 132
    assert receipt["replayed"] is False

    # 同一个幂等键重放不再扣款、不再创建第二笔订单。
    replay = client.post(
        "/api/v1/live/rooms/11/gifts",
        json={"giftId": 1, "quantity": 2, "idempotencyKey": "gift-transaction-001"},
    )
    assert replay.status_code == 200
    assert replay.json()["data"]["replayed"] is True
    assert db.query(GiftTransaction).count() == 1
    assert client.get("/api/v1/wallet").json()["data"]["availableBalance"] == 868

    ledger = client.get("/api/v1/wallet/ledger").json()["data"]
    assert [(item["businessType"], item["amount"]) for item in ledger] == [
        ("gift_spend", -132),
        ("test_grant", 1000),
    ]
    stats = client.get("/api/v1/live/rooms/11/gift-stats").json()["data"]
    assert stats["totalRevenue"] == 132
    assert stats["totalGiftCount"] == 2
    assert stats["topSupporters"] == [
        {"userId": 1, "userName": "观众", "totalAmount": 132, "giftCount": 2}
    ]
    records = client.get("/api/v1/live/rooms/11/gift-records").json()["data"]
    assert records[0]["giftName"] == "玫瑰"

    # 主播的礼物收益也写入独立余额快照和不可变流水，但当前不能提现或消费。
    current["user"] = db.get(User, 2)
    anchor_wallet = client.get("/api/v1/wallet").json()["data"]
    assert anchor_wallet["incomeBalance"] == 132
    assert client.get("/api/v1/wallet/ledger").json()["data"][0]["businessType"] == "gift_income"


def test_gift_rejects_insufficient_balance_and_foreign_idempotency_key(wallet_api):
    client, db, current = wallet_api
    insufficient = client.post(
        "/api/v1/live/rooms/11/gifts",
        json={"giftId": 1, "quantity": 1, "idempotencyKey": "gift-insufficient-001"},
    )
    assert insufficient.status_code == 409
    assert db.query(GiftTransaction).count() == 0

    client.post(
        "/api/v1/wallet/test-grants",
        json={"amount": 100, "idempotencyKey": "wallet-test-grant-002"},
    )
    client.post(
        "/api/v1/live/rooms/11/gifts",
        json={"giftId": 1, "quantity": 1, "idempotencyKey": "gift-owner-bound-001"},
    )
    current["user"] = db.get(User, 2)
    foreign_replay = client.post(
        "/api/v1/live/rooms/11/gifts",
        json={"giftId": 1, "quantity": 1, "idempotencyKey": "gift-owner-bound-001"},
    )
    assert foreign_replay.status_code == 409
