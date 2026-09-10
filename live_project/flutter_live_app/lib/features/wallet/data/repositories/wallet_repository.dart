import '../models/wallet_models.dart';

abstract interface class WalletRepository {
  Future<WalletSummary> getWallet();
  Future<List<WalletLedgerItem>> getLedger();
  Future<WalletSummary> grantTestCoins({
    required int amount,
    required String idempotencyKey,
  });
  Future<List<GiftCatalogItem>> getGifts();
  Future<GiftTransactionReceipt> sendGift({
    required String roomId,
    required int giftId,
    required int quantity,
    required String idempotencyKey,
  });
  Future<RoomGiftStats> getRoomGiftStats(String roomId);
  Future<List<GiftRecordItem>> getRoomGiftRecords(String roomId);
}
