# flutter_live_media_plugin

iOS 原生媒体引擎的 Flutter Plugin 边界。

当前版本完成 Apple 平台的最小播放链路：

- Pigeon 生成 Dart ↔ Swift 的初始化、播放请求、停止请求接口
- 注册 `flutter_live_media_player_view` PlatformView
- Swift 侧使用系统 `AVPlayer` 播放 HTTP/HTTPS 地址
- PlatformView 使用 `AVPlayerLayer` 渲染视频
- 不打开摄像头，也不处理 RTMP/HTTP-FLV/WebRTC

生成 Pigeon 文件：

```bash
dart run pigeon --input pigeons/live_media_api.dart
```

当前建议使用 HLS 地址验证播放。后续替换 `FlutterLiveMediaEngine` 的 Swift 实现即可接入具体直播 SDK，Flutter 业务层无需改动。

A new Flutter plugin project.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
