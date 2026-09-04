# flutter_live_media_plugin

项目整体调用链请先看 [ARCHITECTURE.md](../../ARCHITECTURE.md)。本插件的链路是：Flutter `FlutterLiveMediaEngine` → Pigeon HostApi → 当前平台原生引擎 → PlatformView；原生状态再通过 Pigeon FlutterApi 返回 Flutter。

iOS/macOS 原生媒体引擎的 Flutter Plugin 边界。

当前版本完成 Apple 和 Android 平台的最小播放链路：

- Pigeon 生成 Dart ↔ Swift/Kotlin 的初始化、播放请求、停止请求接口
- 注册 `flutter_live_media_player_view` PlatformView
- Swift 侧使用系统 `AVPlayer` 播放 HTTP/HTTPS 地址
- Android 侧使用 Media3 ExoPlayer 播放 HTTP/HTTPS 地址
- PlatformView 使用 `AVPlayerLayer` 渲染视频
- Android PlatformView 使用 Media3 `PlayerView` 渲染视频
- Pigeon FlutterApi 回传 initialized、playing、buffering、completed、error、reconnecting、stopped 状态
- 监听播放失败和卡顿，按 1s、2s、4s 进行最多 3 次重连
- 不打开摄像头，也不处理 RTMP/HTTP-FLV/WebRTC

生成 Pigeon 文件：

```bash
dart run pigeon --input pigeons/live_media_api.dart
```

当前建议使用 HLS 地址验证播放。后续替换 `FlutterLiveMediaEngine` 的 Swift/Kotlin 实现即可接入具体直播 SDK，Flutter 业务层无需改动。重连次数、退避策略和播放器状态机将在接入真实直播 SDK 时进一步抽象为配置。

## Android 真机验收

插件示例页已经内置公开 HLS 测试流。连接并授权 Android 真机后执行：

```bash
cd example
flutter run -d <android-device-id>
```

验收步骤：

1. 页面自动播放后，状态应从“正在初始化”经过缓冲变为“播放器播放中”，并能看到视频画面。
2. 临时关闭手机 Wi-Fi 和移动数据，等待播放器回调“重连中”。重连等待时间依次为 1 秒、2 秒、4 秒，最多尝试 3 次。
3. 在重连次数耗尽前恢复网络，状态应重新变为“播放器播放中”；`READY` 后重连次数会清零。
4. 如需看原生证据，可执行 `adb logcat -s FlutterLiveMedia`，重点观察 `READY`、`playback error`、`reconnect scheduled` 和 `reconnect started`。

这次验收使用的是测试视频流，不代表生产直播 CDN 的可用性。生产环境应由房间接口返回真实 `playUrl`，并根据业务需要配置鉴权 Header、超时、重试上限和弱网策略。

A new Flutter plugin project.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
