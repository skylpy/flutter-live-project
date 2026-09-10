import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/wallet_remote_data_source.dart';
import '../../data/models/wallet_models.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/wallet_repository_impl.dart';

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepositoryImpl(
    WalletRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final walletSummaryProvider = FutureProvider.autoDispose<WalletSummary>(
  (ref) => ref.watch(walletRepositoryProvider).getWallet(),
);

final walletLedgerProvider = FutureProvider.autoDispose<List<WalletLedgerItem>>(
  (ref) => ref.watch(walletRepositoryProvider).getLedger(),
);

final giftCatalogProvider = FutureProvider.autoDispose<List<GiftCatalogItem>>(
  (ref) => ref.watch(walletRepositoryProvider).getGifts(),
);

final roomGiftStatsProvider = FutureProvider.autoDispose
    .family<RoomGiftStats, String>(
      (ref, roomId) =>
          ref.watch(walletRepositoryProvider).getRoomGiftStats(roomId),
    );

final roomGiftRecordsProvider = FutureProvider.autoDispose
    .family<List<GiftRecordItem>, String>(
      (ref, roomId) =>
          ref.watch(walletRepositoryProvider).getRoomGiftRecords(roomId),
    );

String walletIdempotencyKey(String scope) =>
    '$scope-${DateTime.now().microsecondsSinceEpoch}';
