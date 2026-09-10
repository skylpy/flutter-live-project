import '../datasources/wallet_remote_data_source.dart';
import '../models/wallet_models.dart';
import 'wallet_repository.dart';

class WalletRepositoryImpl implements WalletRepository {
  const WalletRepositoryImpl(this._dataSource);

  final WalletRemoteDataSource _dataSource;

  @override
  Future<WalletSummary> getWallet() => _dataSource.getWallet();

  @override
  Future<List<WalletLedgerItem>> getLedger() => _dataSource.getLedger();

  @override
  Future<WalletSummary> grantTestCoins({
    required int amount,
    required String idempotencyKey,
  }) => _dataSource.grantTestCoins(
    amount: amount,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<List<GiftCatalogItem>> getGifts() => _dataSource.getGifts();

  @override
  Future<GiftTransactionReceipt> sendGift({
    required String roomId,
    required int giftId,
    required int quantity,
    required String idempotencyKey,
  }) => _dataSource.sendGift(
    roomId: roomId,
    giftId: giftId,
    quantity: quantity,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<RoomGiftStats> getRoomGiftStats(String roomId) =>
      _dataSource.getRoomGiftStats(roomId);

  @override
  Future<List<GiftRecordItem>> getRoomGiftRecords(String roomId) =>
      _dataSource.getRoomGiftRecords(roomId);
}
