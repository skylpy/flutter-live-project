import 'package:flutter/material.dart';

/// 直播 Tab 占位页面，未来可以展示分类频道或热门直播。
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('直播')),
      body: Center(child: Text('直播频道即将开放')),
    );
  }
}
