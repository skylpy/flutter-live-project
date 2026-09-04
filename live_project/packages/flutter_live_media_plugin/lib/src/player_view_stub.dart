import 'package:flutter/widgets.dart';

/// 非 OpenHarmony 平台的播放器视图实现。
///
/// 这个文件是条件导入的 fallback：标准 Flutter、iOS、Android 和桌面平台
/// 不会看到 OpenHarmony 专用的 `Texture`/`OhosView` 代码，因此仍然可以用
/// 当前 Flutter 3.47 / Dart 3.13 正常分析和编译。
Widget buildLiveMediaPlayerView() {
  return const ColoredBox(
    color: Color(0xFF080808),
    child: Center(child: Text('原生播放器视图待支持当前平台')),
  );
}
