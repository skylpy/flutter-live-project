# flutter_live_media_plugin

iOS 原生媒体引擎的 Flutter Plugin 边界。

当前版本只完成通信和视图占位：

- Pigeon 生成 Dart ↔ Swift 的初始化、播放请求、停止请求接口
- 注册 `flutter_live_media_player_view` PlatformView
- Swift 侧提供黑色播放器占位视图
- 不接入真实播放器 SDK，不打开摄像头，也不处理 RTMP/HLS/WebRTC

生成 Pigeon 文件：

```bash
dart run pigeon --input pigeons/live_media_api.dart
```

后续替换 `FlutterLiveMediaEngine` 的 Swift 实现即可接入具体播放器，Flutter 业务层无需改动。

A new Flutter plugin project.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
