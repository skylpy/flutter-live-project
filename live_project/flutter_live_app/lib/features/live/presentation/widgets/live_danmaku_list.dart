import 'package:flutter/material.dart';

import '../../data/models/live_chat_message.dart';

/// 直播间内主播和观众共用的实时弹幕叠加层。
class LiveDanmakuList extends StatelessWidget {
  const LiveDanmakuList({required this.messages, super.key});

  final List<LiveChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in messages)
          _LiveDanmakuLine(
            name: item.type == 'chat' ? item.userName : '',
            message: item.message.isNotEmpty
                ? item.message
                : '${item.userName}${item.event == 'joined' ? '进入直播间' : '离开直播间'}',
            system: item.type != 'chat',
          ),
      ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            system ? message : '$name：$message',
            style: TextStyle(
              color: system ? Colors.white70 : Colors.white,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
