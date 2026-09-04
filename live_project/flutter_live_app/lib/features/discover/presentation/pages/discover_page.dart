import 'package:flutter/material.dart';

/// 发现 Tab 的占位页面，后续可接分类、推荐和搜索功能。
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('发现')),
      body: Center(child: Text('发现更多精彩内容')),
    );
  }
}
