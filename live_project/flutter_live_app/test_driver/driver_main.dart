import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_live_app/app/app.dart';

/// Profile 真机验收专用入口。
///
/// 普通 App 入口不引入 flutter_driver；只有 flutter drive 使用这个入口时，
/// 才打开 Driver 扩展，避免把测试控制接口带入普通构建。
void main() {
  enableFlutterDriverExtension();
  runApp(const ProviderScope(child: LiveApp()));
}
