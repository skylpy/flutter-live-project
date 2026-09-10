import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../wallet/data/models/wallet_models.dart';
import '../../../wallet/presentation/controllers/wallet_controller.dart';

/// 直播间送礼面板。余额和价格均来自服务端，提交时由服务端原子扣款。
class LiveGiftSheet extends ConsumerStatefulWidget {
  const LiveGiftSheet({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<LiveGiftSheet> createState() => _LiveGiftSheetState();
}

class _LiveGiftSheetState extends ConsumerState<LiveGiftSheet> {
  GiftCatalogItem? _selected;
  WalletSummary? _wallet;
  int _quantity = 1;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(walletRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.getWallet(),
        repository.getGifts(),
      ]);
      if (!mounted) return;
      final gifts = results[1] as List<GiftCatalogItem>;
      setState(() {
        _wallet = results[0] as WalletSummary;
        _selected = gifts.contains(_selected) ? _selected : gifts.firstOrNull;
        _loading = false;
      });
      ref.invalidate(giftCatalogProvider);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _claimTestCoins() async {
    setState(() => _submitting = true);
    try {
      final wallet = await ref
          .read(walletRepositoryProvider)
          .grantTestCoins(
            amount: 1000,
            idempotencyKey: walletIdempotencyKey('test-coin'),
          );
      if (!mounted) return;
      setState(() => _wallet = wallet);
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(walletLedgerProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('测试金币已到账：+1000')));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _sendGift() async {
    final gift = _selected;
    if (gift == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final receipt = await ref
          .read(walletRepositoryProvider)
          .sendGift(
            roomId: widget.roomId,
            giftId: gift.id,
            quantity: _quantity,
            idempotencyKey: walletIdempotencyKey('gift'),
          );
      if (!mounted) return;
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(walletLedgerProvider);
      ref.invalidate(roomGiftStatsProvider(widget.roomId));
      Navigator.of(context).pop(receipt);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gifts =
        ref.watch(giftCatalogProvider).asData?.value ??
        const <GiftCatalogItem>[];
    final wallet = _wallet;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 370,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _GiftLoadError(message: _error!, onRetry: _reload)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
                    child: Row(
                      children: [
                        const Text(
                          '送礼物',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${wallet?.currencyName ?? '金币'} ${wallet?.availableBalance ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (wallet?.testMode == true)
                          TextButton(
                            onPressed: _submitting ? null : _claimTestCoins,
                            child: const Text('领测试金币'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: .91,
                          ),
                      itemCount: gifts.length,
                      itemBuilder: (context, index) {
                        final gift = gifts[index];
                        final selected = _selected?.id == gift.id;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _selected = gift),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xffffedf6)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? Colors.pinkAccent
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  gift.icon,
                                  style: const TextStyle(fontSize: 35),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  gift.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '${gift.price} 金币',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _quantity > 1 && !_submitting
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$_quantity',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: _quantity < 99 && !_submitting
                              ? () => setState(() => _quantity++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _selected == null || _submitting
                              ? null
                              : _sendGift,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.pinkAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 13,
                            ),
                          ),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(
                            _selected == null
                                ? '选择礼物'
                                : '${(_selected!.price * _quantity)} 金币送出',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GiftLoadError extends StatelessWidget {
  const _GiftLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

Future<GiftTransactionReceipt?> showLiveGiftSheet(
  BuildContext context, {
  required String roomId,
}) => showModalBottomSheet<GiftTransactionReceipt>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  showDragHandle: true,
  builder: (context) => LiveGiftSheet(roomId: roomId),
);
