import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Flutter 应用入口。
///
/// 这里只负责组装根节点。ProviderScope 提供 Riverpod 的全局状态容器，
/// 页面、路由和业务逻辑分别放在 app、core、features 目录中。
void main() {
  runApp(const ProviderScope(child: LiveApp()));
}
