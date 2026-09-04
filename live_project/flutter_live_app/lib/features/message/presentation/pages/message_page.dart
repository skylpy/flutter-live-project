import 'package:flutter/material.dart';

/// 消息 Tab 占位页，未来承载私信、系统通知和互动消息。
class MessagePage extends StatelessWidget {
  const MessagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('消息')),
      body: Center(child: Text('暂无消息')),
    );
  }
}
