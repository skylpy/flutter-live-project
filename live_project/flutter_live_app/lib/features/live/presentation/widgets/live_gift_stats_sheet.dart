import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../wallet/presentation/controllers/wallet_controller.dart';

/// 直播间礼物贡献榜与最近送礼记录。
class LiveGiftStatsSheet extends ConsumerWidget {
  const LiveGiftStatsSheet({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(roomGiftStatsProvider(roomId));
    final records = ref.watch(roomGiftRecordsProvider(roomId));
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 520,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: Color(0xffff9b30)),
                  SizedBox(width: 8),
                  Text(
                    '礼物榜单',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            stats.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
              error: (error, _) => _StatsError(
                message: error.toString(),
                onRetry: () => ref.invalidate(roomGiftStatsProvider(roomId)),
              ),
              data: (value) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _Metric(label: '本场收益', value: '${value.totalRevenue}'),
                    const SizedBox(width: 34),
                    _Metric(label: '收到礼物', value: '${value.totalGiftCount}'),
                    const Spacer(),
                    Text(
                      '单位：金币',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: .45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                children: [
                  const Text(
                    '贡献榜',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  stats.when(
                    loading: () => const SizedBox(height: 52),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (value) => value.topSupporters.isEmpty
                        ? const _SheetEmpty(text: '还没有人送出礼物')
                        : Card(
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < value.topSupporters.length;
                                  index++
                                )
                                  ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: const Color(0xffffeff7),
                                      child: Text('${index + 1}'),
                                    ),
                                    title: Text(
                                      value.topSupporters[index].userName,
                                    ),
                                    subtitle: Text(
                                      '${value.topSupporters[index].giftCount} 件礼物',
                                    ),
                                    trailing: Text(
                                      '${value.topSupporters[index].totalAmount}',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '最近送礼',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  records.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _StatsError(
                      message: error.toString(),
                      onRetry: () =>
                          ref.invalidate(roomGiftRecordsProvider(roomId)),
                    ),
                    data: (items) => items.isEmpty
                        ? const _SheetEmpty(text: '暂无送礼记录')
                        : Card(
                            child: Column(
                              children: [
                                for (final item in items)
                                  ListTile(
                                    dense: true,
                                    leading: Text(
                                      item.giftIcon,
                                      style: const TextStyle(fontSize: 26),
                                    ),
                                    title: Text(
                                      '${item.senderName} 送出 ${item.giftName}',
                                    ),
                                    subtitle: Text(item.timeLabel),
                                    trailing: Text(
                                      '×${item.quantity}  ·  ${item.totalAmount}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.black.withValues(alpha: .5),
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
      ),
    ],
  );
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Center(
      child: Text(
        text,
        style: TextStyle(color: Colors.black.withValues(alpha: .45)),
      ),
    ),
  );
}

class _StatsError extends StatelessWidget {
  const _StatsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

Future<void> showLiveGiftStatsSheet(
  BuildContext context, {
  required String roomId,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  showDragHandle: true,
  builder: (context) => LiveGiftStatsSheet(roomId: roomId),
);
