import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel _ohosPlayerChannel = MethodChannel(
  'flutter_live_media_plugin/ohos',
);

/// OpenHarmony 的视频显示控件。
///
/// OpenHarmony 官方视频插件采用外接纹理：ArkTS 的 AVPlayer 把画面输出到
/// Flutter Texture，Dart 侧只需要渲染 textureId。这样不会把 AVPlayer 对象
/// 暴露给业务层，也能保持和 iOS/Android 相同的 LiveEngine 调用链。
Widget buildLiveMediaPlayerView() {
  return const _OhosTextureView();
}

/// PlatformView 兼容占位控件。
///
/// 当前 Flutter SDK 没有稳定的 `OhosView` Dart API，因此统一复用 Texture
/// 路径。未来鸿蒙插件提供稳定的 PlatformView 类型后，只需在这里替换实现，
/// 不影响 LiveEngine 和业务页面。
class FlutterLiveMediaPlatformViewPlaceholder extends StatelessWidget {
  const FlutterLiveMediaPlatformViewPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _OhosTextureView();
  }
}

class _OhosTextureView extends StatefulWidget {
  const _OhosTextureView();

  @override
  State<_OhosTextureView> createState() => _OhosTextureViewState();
}

class _OhosTextureViewState extends State<_OhosTextureView> {
  late final Future<int?> _textureIdFuture = _loadTextureId();

  /// 初始化和播放器视图创建存在时序差异，因此短暂轮询 textureId。
  ///
  /// 页面首帧创建控件时，原生播放器可能还没有收到 initialize；轮询可以
  /// 避免把这类正常竞态误判为错误。超过约 3 秒仍未拿到纹理时显示占位文案。
  Future<int?> _loadTextureId() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      final textureId = await _ohosPlayerChannel.invokeMethod<int>(
        'getTextureId',
      );
      if (textureId != null && textureId >= 0) return textureId;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _textureIdFuture,
      builder: (context, snapshot) {
        final textureId = snapshot.data;
        if (textureId == null) {
          return const ColoredBox(
            color: Color(0xFF080808),
            child: Center(child: Text('鸿蒙播放器纹理初始化中')),
          );
        }
        return Texture(textureId: textureId);
      },
    );
  }
}
