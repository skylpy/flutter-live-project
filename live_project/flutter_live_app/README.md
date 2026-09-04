# flutter_live_app

建议先阅读项目根目录的 [ARCHITECTURE.md](../ARCHITECTURE.md)。客户端的基本链路是：页面 → Riverpod Controller → Repository → DataSource → ApiClient → FastAPI。

`lib/core/media` 只暴露 `LiveEngine` 抽象，直播间不会直接依赖 AVPlayer、ExoPlayer 或 Pigeon；平台播放器位于 `../packages/flutter_live_media_plugin`。

Flutter 直播客户端第一阶段。依赖 Flutter 3.47.2 / Dart 3.13.2，使用 Riverpod、go_router、Dio 和 Material 3。

```bash
flutter pub get
dart format .
flutter analyze
flutter run
```

默认请求 `http://localhost:8000/api/v1`。Android Emulator 请使用：

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

当前客户端包含五个 Tab、真实 API 直播列表、详情请求、加载/错误/重试/下拉刷新、登录/注册、JWT Token 持久化及播放器占位 UI；登录后可在直播间连接 WebSocket 发送弹幕。
