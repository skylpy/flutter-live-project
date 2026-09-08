import 'package:flutter/material.dart';

import '../../data/models/live_chat_message.dart';

/// 直播间内主播和观众共用的实时弹幕叠加层。
class LiveDanmakuList extends StatefulWidget {
  const LiveDanmakuList({required this.messages, super.key});

  final List<LiveChatMessage> messages;

  @override
  State<LiveDanmakuList> createState() => _LiveDanmakuListState();
}

class _LiveDanmakuListState extends State<LiveDanmakuList> {
  static const _maxHeight = 190.0;
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LiveDanmakuList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        // reverse 列表的 0 位置就是最新消息；用户已经上翻时不打断阅读。
        if (_scrollController.position.pixels <= 24) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          maxHeight: _maxHeight,
        ),
        child: ListView.builder(
          controller: _scrollController,
          reverse: true,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: widget.messages.length,
          itemBuilder: (context, reverseIndex) {
            final item =
                widget.messages[widget.messages.length - 1 - reverseIndex];
            return Align(
              alignment: Alignment.centerLeft,
              child: _LiveDanmakuLine(
                name: item.type == 'chat' ? item.userName : '',
                message: item.message.isNotEmpty
                    ? item.message
                    : '${item.userName}${item.event == 'joined' ? '进入直播间' : '离开直播间'}',
                system: item.type != 'chat',
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiveDanmakuLine extends StatelessWidget {
  const _LiveDanmakuLine({
    required this.name,
    required this.message,
    required this.system,
  });

  final String name;
  final String message;
  final bool system;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            system ? message : '$name：$message',
            style: TextStyle(
              color: system ? Colors.white70 : Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
