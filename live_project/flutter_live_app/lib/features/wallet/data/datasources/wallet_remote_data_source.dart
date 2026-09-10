import '../../../../core/network/api_client.dart';
import '../models/wallet_models.dart';

/// 钱包 REST 数据源；余额、价格与账本都以服务端响应为准。
class WalletRemoteDataSource {
  const WalletRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<WalletSummary> getWallet() => _apiClient
      .get<WalletSummary>('/wallet', parseData: _wallet)
      .then((response) => response.data);

  Future<List<WalletLedgerItem>> getLedger() => _apiClient
      .get<List<WalletLedgerItem>>(
        '/wallet/ledger',
        parseData: (value) {
          final rows = value is List ? value : const <Object?>[];
          return rows
              .whereType<Map>()
              .map(
                (item) =>
                    WalletLedgerItem.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false);
        },
      )
      .then((response) => response.data);

  Future<WalletSummary> grantTestCoins({
    required int amount,
    required String idempotencyKey,
  }) => _apiClient
      .post<WalletSummary>(
        '/wallet/test-grants',
        data: <String, Object?>{
          'amount': amount,
          'idempotencyKey': idempotencyKey,
        },
        parseData: _wallet,
      )
      .then((response) => response.data);

  Future<List<GiftCatalogItem>> getGifts() => _apiClient
      .get<List<GiftCatalogItem>>(
        '/gifts',
        parseData: (value) {
          final rows = value is List ? value : const <Object?>[];
          return rows
              .whereType<Map>()
              .map(
                (item) =>
                    GiftCatalogItem.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false);
        },
      )
      .then((response) => response.data);

  Future<GiftTransactionReceipt> sendGift({
    required String roomId,
    required int giftId,
    required int quantity,
    required String idempotencyKey,
  }) => _apiClient
      .post<GiftTransactionReceipt>(
        '/live/rooms/$roomId/gifts',
        data: <String, Object?>{
          'giftId': giftId,
          'quantity': quantity,
          'idempotencyKey': idempotencyKey,
        },
        parseData: _receipt,
      )
      .then((response) => response.data);

  Future<RoomGiftStats> getRoomGiftStats(String roomId) => _apiClient
      .get<RoomGiftStats>('/live/rooms/$roomId/gift-stats', parseData: _stats)
      .then((response) => response.data);

  Future<List<GiftRecordItem>> getRoomGiftRecords(String roomId) => _apiClient
      .get<List<GiftRecordItem>>(
        '/live/rooms/$roomId/gift-records',
        parseData: (value) {
          final rows = value is List ? value : const <Object?>[];
          return rows
              .whereType<Map>()
              .map(
                (item) =>
                    GiftRecordItem.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false);
        },
      )
      .then((response) => response.data);

  WalletSummary _wallet(Object? value) {
    if (value is! Map) throw const FormatException('钱包数据格式不正确');
    return WalletSummary.fromJson(Map<String, Object?>.from(value));
  }

  GiftTransactionReceipt _receipt(Object? value) {
    if (value is! Map) throw const FormatException('送礼结果格式不正确');
    return GiftTransactionReceipt.fromJson(Map<String, Object?>.from(value));
  }

  RoomGiftStats _stats(Object? value) {
    if (value is! Map) throw const FormatException('礼物统计格式不正确');
    return RoomGiftStats.fromJson(Map<String, Object?>.from(value));
  }
}
