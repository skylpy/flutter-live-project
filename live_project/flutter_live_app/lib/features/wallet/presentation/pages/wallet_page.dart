import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/wallet_controller.dart';

/// 我的钱包：可消费金币、主播礼物收益，以及不可变流水的用户可见入口。
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  bool _claiming = false;

  Future<void> _claimTestCoins() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      await ref
          .read(walletRepositoryProvider)
          .grantTestCoins(
            amount: 1000,
            idempotencyKey: walletIdempotencyKey('wallet-test'),
          );
      ref.invalidate(walletSummaryProvider);
      ref.invalidate(walletLedgerProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('测试金币已到账：+1000')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    final wallet = ref.watch(walletSummaryProvider);
    final ledgers = ref.watch(walletLedgerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的钱包')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletSummaryProvider);
          ref.invalidate(walletLedgerProvider);
          await ref.read(walletSummaryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            wallet.when(
              loading: () => const _WalletLoadingCard(),
              error: (error, _) => _WalletLoadError(
                message: error.toString(),
                onRetry: () => ref.invalidate(walletSummaryProvider),
              ),
              data: (data) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff39245f), Color(0xffe64f9e)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.currencyName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${data.availableBalance}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _WalletMetric(
                            label: data.incomeName,
                            value: '${data.incomeBalance}',
                          ),
                        ),
                        if (data.testMode)
                          FilledButton(
                            onPressed: _claiming ? null : _claimTestCoins,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: tokens.primary,
                            ),
                            child: _claiming
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('领取测试金币'),
                          ),
                      ],
                    ),
                    if (data.testMode) ...[
                      const SizedBox(height: 10),
                      const Text(
                        '当前为测试金币，不涉及真实充值或提现。',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '金币明细',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ledgers.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => _WalletLoadError(
                message: error.toString(),
                onRetry: () => ref.invalidate(walletLedgerProvider),
              ),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无金币明细')),
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final item in items)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: item.amount >= 0
                                    ? const Color(0xffffecf5)
                                    : const Color(0xfff1ecff),
                                child: Icon(
                                  item.amount >= 0
                                      ? Icons.add_circle_outline
                                      : Icons.card_giftcard_outlined,
                                  color: item.amount >= 0
                                      ? Colors.pinkAccent
                                      : const Color(0xff7559c7),
                                ),
                              ),
                              title: Text(item.title),
                              subtitle: Text(
                                '${item.timeLabel} · 余额 ${item.balanceAfter}',
                              ),
                              trailing: Text(
                                '${item.amount >= 0 ? '+' : ''}${item.amount}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: item.amount >= 0
                                      ? const Color(0xffd94886)
                                      : Colors.black87,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _WalletLoadingCard extends StatelessWidget {
  const _WalletLoadingCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 190,
    decoration: BoxDecoration(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _WalletLoadError extends StatelessWidget {
  const _WalletLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}
