import 'package:flutter/material.dart';

import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';

/// 直播间的视频区域。
///
/// 播放链路由两层组成：
///
/// 1. [FlutterLiveMediaPlayerView] 负责承载平台播放器输出。鸿蒙平台使用
///    AVPlayer → SurfaceTexture → Flutter Texture，iOS/Android 由插件选择
///    各自的原生视图实现。
/// 2. 本 Widget 只负责 Flutter 侧的视觉状态，不创建或操作原生播放器。
///
/// 这样做的好处是：播放器重连时只替换原生 AVPlayer，页面仍然保持同一个
/// 布局和 Texture；将来接入预加载、清晰度切换或全屏手势时，也不会把业务
/// 页面和具体平台 API 绑在一起。
class LiveRoomPlayer extends StatelessWidget {
  const LiveRoomPlayer({required this.status, super.key});

  final String? status;

  bool get _hasPlayableState => status != null && status!.isNotEmpty;

  bool get _showPlaceholder => status == null || status!.contains('未配置播放地址');

  bool get _showStatusChip =>
      _hasPlayableState &&
      (status!.contains('缓冲') ||
          status!.contains('重连') ||
          status!.contains('错误') ||
          status!.contains('失败'));

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 这是正式直播间页面的真实播放器入口，不是单纯的黑色占位框。
        // 非鸿蒙平台由插件内部选择 UiKitView/AppKitView/AndroidView。
        const Positioned.fill(child: FlutterLiveMediaPlayerView()),
        if (_showPlaceholder)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv, color: Colors.white60, size: 64),
                    SizedBox(height: 16),
                    Text(
                      '播放器区域',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    SizedBox(height: 6),
                    Text('等待直播播放地址', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
          ),
        if (_showStatusChip)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _PlayerStatusChip(message: status!),
          ),
      ],
    );
  }
}

/// 只显示异常或缓冲状态，避免正常播放时遮挡视频画面。
class _PlayerStatusChip extends StatelessWidget {
  const _PlayerStatusChip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isRecovering = message.contains('重连') || message.contains('缓冲');
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: const BorderRadius.all(Radius.circular(18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRecovering) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
