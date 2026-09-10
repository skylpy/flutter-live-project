import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/live_chat_message.dart';

/// 房间中所有客户端共用的礼物动画队列。
///
/// 事件输入只来自已被服务端确认且广播的礼物。动画按总价值分级并排队：
/// 城堡等高等级礼物会排在普通礼物之前，且使用更长、更大范围的展示；不会
/// 因为连续到达的事件而被后一个礼物直接覆盖、丢失。
class LiveGiftEffect extends StatefulWidget {
  const LiveGiftEffect({required this.gift, super.key});

  final LiveGiftEvent? gift;

  @override
  State<LiveGiftEffect> createState() => _LiveGiftEffectState();
}

class _LiveGiftEffectState extends State<LiveGiftEffect> {
  static const _intermission = Duration(milliseconds: 120);

  final List<LiveGiftEvent> _waiting = <LiveGiftEvent>[];
  final List<int> _seenEventIds = <int>[];
  LiveGiftEvent? _activeGift;
  Timer? _nextTimer;

  @override
  void initState() {
    super.initState();
    _enqueue(widget.gift, notify: false);
  }

  @override
  void didUpdateWidget(covariant LiveGiftEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gift?.id != oldWidget.gift?.id) {
      _enqueue(widget.gift);
    }
  }

  @override
  void dispose() {
    _nextTimer?.cancel();
    super.dispose();
  }

  void _enqueue(LiveGiftEvent? event, {bool notify = true}) {
    if (event == null || _seenEventIds.contains(event.id)) return;

    _seenEventIds.add(event.id);
    // 保留一小段去重窗口，既防止同一 WebSocket 事件重放，也不会无限增长。
    if (_seenEventIds.length > 80) _seenEventIds.removeAt(0);
    // 正在展示普通礼物时收到更高级礼物，先把普通礼物放回等待队列，让高
    // 级礼物立即抢占舞台；普通礼物随后会继续完整展示，不会被丢弃。
    final active = _activeGift;
    if (active != null &&
        event.visualTier.priority > active.visualTier.priority) {
      _waiting.add(active);
      _activeGift = null;
    }
    _waiting.add(event);
    _waiting.sort((left, right) {
      final tierOrder = right.visualTier.priority.compareTo(
        left.visualTier.priority,
      );
      return tierOrder != 0 ? tierOrder : left.id.compareTo(right.id);
    });

    if (_activeGift == null) _showNext(notify: notify);
  }

  void _showNext({bool notify = true}) {
    if (!mounted || _activeGift != null || _waiting.isEmpty) return;
    final next = _waiting.removeAt(0);
    if (notify) {
      setState(() => _activeGift = next);
    } else {
      _activeGift = next;
    }
  }

  void _complete(int eventId) {
    if (!mounted || _activeGift?.id != eventId) return;
    setState(() => _activeGift = null);
    _nextTimer?.cancel();
    _nextTimer = Timer(_intermission, _showNext);
  }

  @override
  Widget build(BuildContext context) {
    final gift = _activeGift;
    if (gift == null) return const SizedBox.expand();
    return IgnorePointer(
      child: _GiftAnimation(
        key: ValueKey<int>(gift.id),
        gift: gift,
        onCompleted: () => _complete(gift.id),
      ),
    );
  }
}

enum _GiftVisualTier { normal, premium, epic, legendary }

extension on LiveGiftEvent {
  _GiftVisualTier get visualTier {
    // 优先使用服务端礼物目录的动画键，金额则处理一次送多件礼物的升级情况。
    if (animationKey == 'castle' || totalAmount >= 999) {
      return _GiftVisualTier.legendary;
    }
    if (animationKey == 'starlight' || totalAmount >= 199) {
      return _GiftVisualTier.epic;
    }
    if (animationKey == 'rose' || totalAmount >= 66) {
      return _GiftVisualTier.premium;
    }
    return _GiftVisualTier.normal;
  }
}

extension on _GiftVisualTier {
  int get priority => switch (this) {
    _GiftVisualTier.normal => 1,
    _GiftVisualTier.premium => 2,
    _GiftVisualTier.epic => 3,
    _GiftVisualTier.legendary => 4,
  };

  Duration get duration => switch (this) {
    _GiftVisualTier.normal => const Duration(milliseconds: 2800),
    _GiftVisualTier.premium => const Duration(milliseconds: 3800),
    _GiftVisualTier.epic => const Duration(milliseconds: 5200),
    _GiftVisualTier.legendary => const Duration(milliseconds: 6800),
  };
}

class _GiftAnimation extends StatelessWidget {
  const _GiftAnimation({
    required this.gift,
    required this.onCompleted,
    super.key,
  });

  final LiveGiftEvent gift;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) => switch (gift.visualTier) {
    _GiftVisualTier.normal => _CompactGiftAnimation(
      gift: gift,
      onCompleted: onCompleted,
      premium: false,
    ),
    _GiftVisualTier.premium => _CompactGiftAnimation(
      gift: gift,
      onCompleted: onCompleted,
      premium: true,
    ),
    _GiftVisualTier.epic => _EpicGiftAnimation(
      gift: gift,
      onCompleted: onCompleted,
    ),
    _GiftVisualTier.legendary => _LegendaryGiftAnimation(
      gift: gift,
      onCompleted: onCompleted,
    ),
  };
}

class _CompactGiftAnimation extends StatelessWidget {
  const _CompactGiftAnimation({
    required this.gift,
    required this.onCompleted,
    required this.premium,
  });

  final LiveGiftEvent gift;
  final VoidCallback onCompleted;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final duration = gift.visualTier.duration;
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      onEnd: onCompleted,
      builder: (context, progress, child) {
        final opacity = _giftOpacity(progress);
        final entrance = Curves.elasticOut.transform(
          (progress * 2.2).clamp(0, 1),
        );
        return Opacity(
          opacity: opacity,
          child: Align(
            alignment: Alignment(0, premium ? 0.32 : 0.5),
            child: Transform.translate(
              offset: Offset(0, 130 * (1 - entrance) - 44 * progress),
              child: Transform.scale(
                scale: 0.72 + entrance * 0.28,
                child: child,
              ),
            ),
          ),
        );
      },
      child: _GiftCard(gift: gift, premium: premium),
    );
  }
}

class _EpicGiftAnimation extends StatelessWidget {
  const _EpicGiftAnimation({required this.gift, required this.onCompleted});

  final LiveGiftEvent gift;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        duration: gift.visualTier.duration,
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: 1),
        onEnd: onCompleted,
        builder: (context, progress, child) {
          final entrance = Curves.elasticOut.transform(
            (progress * 1.8).clamp(0, 1),
          );
          return Opacity(
            opacity: _giftOpacity(progress),
            child: Stack(
              children: [
                for (var index = 0; index < 12; index++)
                  _sparkle(
                    constraints,
                    index,
                    progress,
                    icon: index.isEven ? '✦' : '✧',
                    color: const Color(0xfffff0ad),
                    size: 18 + (index % 3) * 7,
                  ),
                Align(
                  alignment: const Alignment(0, -0.02),
                  child: Transform.scale(
                    scale: 0.52 + entrance * 0.48,
                    child: Transform.rotate(
                      angle: progress * math.pi * .08,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: _EpicGiftCard(gift: gift),
      ),
    );
  }
}

class _LegendaryGiftAnimation extends StatelessWidget {
  const _LegendaryGiftAnimation({
    required this.gift,
    required this.onCompleted,
  });

  final LiveGiftEvent gift;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        duration: gift.visualTier.duration,
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: 1),
        onEnd: onCompleted,
        builder: (context, progress, child) {
          final entrance = Curves.elasticOut.transform(
            (progress * 1.45).clamp(0, 1),
          );
          final haloScale = .6 + math.sin(progress * math.pi) * .55;
          return Opacity(
            opacity: _giftOpacity(progress),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xffffd766).withValues(alpha: .44),
                        const Color(0xff4d1d91).withValues(alpha: .30),
                        Colors.black.withValues(alpha: .38),
                      ],
                      stops: const [0, .48, 1],
                    ),
                  ),
                ),
                Align(
                  child: Transform.scale(
                    scale: haloScale,
                    child: Container(
                      width: math.min(constraints.maxWidth * .88, 390),
                      height: math.min(constraints.maxWidth * .88, 390),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xfffff3a0).withValues(alpha: .72),
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xffffc64a),
                            blurRadius: 54,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < 20; index++)
                  _sparkle(
                    constraints,
                    index,
                    progress,
                    icon: index % 3 == 0 ? '✦' : '✧',
                    color: index.isEven
                        ? const Color(0xffffe680)
                        : const Color(0xffff9ee9),
                    size: 18 + (index % 4) * 7,
                    radius: .38,
                  ),
                Align(
                  alignment: const Alignment(0, -0.05),
                  child: Transform.scale(
                    scale: .4 + entrance * .6,
                    child: child,
                  ),
                ),
              ],
            ),
          );
        },
        child: _LegendaryGiftCard(gift: gift),
      ),
    );
  }
}

Widget _sparkle(
  BoxConstraints constraints,
  int index,
  double progress, {
  required String icon,
  required Color color,
  required double size,
  double radius = .25,
}) {
  final angle = (index * 2.39996) + progress * math.pi * 2;
  final x =
      constraints.maxWidth * .5 +
      math.cos(angle) * constraints.maxWidth * radius;
  final y =
      constraints.maxHeight * .46 +
      math.sin(angle * 1.25) * constraints.maxHeight * radius;
  return Positioned(
    left: x - size / 2,
    top: y - size / 2,
    child: Opacity(
      opacity: (.35 + math.sin(progress * math.pi * 6 + index).abs() * .65)
          .clamp(0, 1),
      child: Transform.scale(
        scale: .65 + math.sin(progress * math.pi * 4 + index).abs() * .65,
        child: Text(
          icon,
          style: TextStyle(color: color, fontSize: size),
        ),
      ),
    ),
  );
}

double _giftOpacity(double progress) {
  if (progress < .10) return Curves.easeOut.transform(progress / .10);
  if (progress < .78) return 1;
  return Curves.easeIn.transform((1 - progress) / .22);
}

class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.gift, required this.premium});

  final LiveGiftEvent gift;
  final bool premium;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: premium
            ? const [Color(0xffffa53d), Color(0xffff487e), Color(0xff9544eb)]
            : const [Color(0xffff4f9b), Color(0xffff9a58)],
      ),
      borderRadius: BorderRadius.circular(30),
      border: premium
          ? Border.all(color: const Color(0xffffeda2), width: 1.5)
          : null,
      boxShadow: const [
        BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 7)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(gift.giftIcon, style: TextStyle(fontSize: premium ? 42 : 31)),
          const SizedBox(width: 9),
          _GiftText(gift: gift, titleSize: premium ? 18 : 16),
        ],
      ),
    ),
  );
}

class _EpicGiftCard extends StatelessWidget {
  const _EpicGiftCard({required this.gift});

  final LiveGiftEvent gift;

  @override
  Widget build(BuildContext context) => Container(
    width: 258,
    padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff6c3be6), Color(0xffdb5bff), Color(0xffffca58)],
      ),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white70, width: 1.5),
      boxShadow: const [
        BoxShadow(color: Color(0xffb961ff), blurRadius: 32, spreadRadius: 4),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '璀璨礼物降临',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(gift.giftIcon, style: const TextStyle(fontSize: 78)),
        _GiftText(gift: gift, centered: true, titleSize: 22),
      ],
    ),
  );
}

class _LegendaryGiftCard extends StatelessWidget {
  const _LegendaryGiftCard({required this.gift});

  final LiveGiftEvent gift;

  @override
  Widget build(BuildContext context) => Container(
    width: 310,
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xffffe28b), Color(0xffffa94d), Color(0xffc648a0)],
      ),
      borderRadius: BorderRadius.circular(44),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(color: Color(0xffffd365), blurRadius: 38, spreadRadius: 8),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '全屏荣耀礼物',
          style: TextStyle(
            color: Color(0xff723315),
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 7),
        Text(gift.giftIcon, style: const TextStyle(fontSize: 126)),
        _GiftText(gift: gift, centered: true, titleSize: 27, dark: true),
      ],
    ),
  );
}

class _GiftText extends StatelessWidget {
  const _GiftText({
    required this.gift,
    required this.titleSize,
    this.centered = false,
    this.dark = false,
  });

  final LiveGiftEvent gift;
  final double titleSize;
  final bool centered;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? const Color(0xff592719) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          gift.senderName,
          style: TextStyle(color: color.withValues(alpha: .86), fontSize: 12),
        ),
        Text(
          '${gift.giftName} × ${gift.quantity}',
          style: TextStyle(
            color: color,
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
