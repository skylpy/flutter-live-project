# Flutter Live 项目阅读指南

这份文档和源码注释一起使用。目标是让只掌握基础 Dart、Flutter 和 Python 的开发人员，能够先看懂项目的主链路，再逐步进入具体实现。

## 1. 项目分层

```text
live_project/
├── flutter_live_app/                 # Flutter 客户端
│   ├── lib/app/                      # App 根节点和路由
│   ├── lib/core/                     # 全局基础设施：网络、认证、主题、媒体边界
│   ├── lib/features/                 # 按业务功能拆分：首页、直播、登录等
│   └── lib/shared/                   # 多个功能共同使用的组件
├── flutter_live_server/              # FastAPI 服务端
│   ├── app/api/                      # HTTP/WebSocket 接口层
│   ├── app/schemas/                  # 请求和响应的数据格式
│   ├── app/services/                 # 业务规则
│   ├── app/repositories/             # 数据库读写
│   ├── app/models/                   # SQLAlchemy 数据库模型
│   └── alembic/                      # 数据库迁移
└── packages/
    ├── flutter_live_core/            # Flutter 与原生播放器共同遵守的抽象协议
    └── flutter_live_media_plugin/    # Pigeon、PlatformView 和原生播放器实现
```

分层的核心规则是：页面只负责展示和响应用户操作；Controller 负责状态；Repository 负责“从哪里取数据”；DataSource 负责具体 HTTP/WebSocket 调用；原生播放器只通过 Plugin 边界被 Flutter 使用。

## 2. Flutter 启动链路

```text
main.dart
  → ProviderScope
  → LiveApp
  → MaterialApp.router
  → appRouter
  → StatefulShellRoute.indexedStack
  → MainScaffold + 当前 Tab Branch
```

`ProviderScope` 是 Riverpod 的根容器。任何 `ConsumerWidget` 或 `ConsumerState` 都可以通过 `ref.watch` 监听状态、通过 `ref.read` 调用业务对象。

`StatefulShellRoute.indexedStack` 为五个 Tab 各自保留 Navigator，因此从首页进入子页面后切换到其他 Tab，再切回来时原来的导航状态不会丢失。直播间路由使用 `parentNavigatorKey: _rootNavigatorKey`，所以它覆盖在 Tab 容器之外，底部 NavigationBar 自然不会显示。

## 3. 首页加载直播列表

```text
HomePage
  → ref.watch(liveListControllerProvider)
  → LiveListController.build()
  → LiveRepository.getLivingRooms()
  → LiveRemoteDataSource.getLivingRooms()
  → ApiClient.get('/live/rooms')
  → FastAPI /api/v1/live/rooms
  → LiveRoomResponse
  → Flutter LiveRoom
  → GridView + LiveRoomCard
```

这里每一层只做一件事：

- `ApiClient` 统一处理 Dio、超时、JWT 和错误翻译。
- `DataSource` 知道 URL 和 JSON 解析方式。
- `Repository` 隔离数据来源，未来可以把 HTTP 换成缓存或其他服务。
- `Controller` 将异步结果转换成 Riverpod 的 loading/data/error 状态。
- 页面只根据状态选择进度条、错误界面或列表。

## 4. 登录链路

```text
LoginPage
  → AuthController.login/register
  → AuthRepository
  → AuthRemoteDataSource
  → ApiClient.post('/auth/login' 或 '/auth/register')
  → FastAPI AuthService
  → UserRepository
  → MySQL users 表
  → JWT + 用户信息
  → TokenStorage(SharedPreferences)
```

下次请求时，`ApiClient` 的请求拦截器会先从 `TokenStorage` 读 Token，再自动加上 `Authorization: Bearer <token>`。页面不需要自己拼请求头，这样可以避免各处重复实现认证逻辑。

## 5. 直播间链路

```text
点击 LiveRoomCard
  → context.push('/live-room/:roomId')
  → root Navigator 打开 LiveRoomPage
  → LiveRoomController 请求房间详情
  → LiveRoomPage 创建 FlutterLiveMediaEngine
  → initialize()
  → play(playUrl)
  → Pigeon HostApi
  → 当前平台原生播放器
  → PlatformView 显示视频
  → Pigeon FlutterApi 回传状态
  → LiveEngineEvent
  → 直播间更新播放器状态文字
```

第一阶段没有真实播放地址时，页面仍然会显示播放器区域和状态占位。这样页面和播放器边界先稳定下来，后续接入 HLS、HTTP-FLV 或 WebRTC 时，不需要重写直播间 UI。

当前平台实现：

- iOS/macOS：Swift + AVPlayer + AVPlayerLayer。
- Android：Kotlin + Media3 ExoPlayer + PlayerView。
- HarmonyOS/OpenHarmony：暂未实现，但可以复用同一个 `LiveEngine` 语义和 Pigeon/插件边界。

## 6. Pigeon 和 PlatformView 是什么

Pigeon 根据 `packages/flutter_live_media_plugin/pigeons/live_media_api.dart` 生成类型安全的跨语言接口。Flutter 调用 `LiveMediaHostApi.initialize/play/stop`，原生调用 `LiveMediaFlutterApi.onEvent` 把播放器事件传回 Flutter。`*.g.dart`、`*.g.swift`、`*.g.kt` 都是生成文件，不应该手工修改；修改接口后重新运行 `dart run pigeon --input pigeons/live_media_api.dart`。

PlatformView 解决的是“把原生 View 放到 Flutter 页面里”：Flutter 端使用 `AndroidView`、`UiKitView` 或 `AppKitView`，原生端注册相同的 `flutter_live_media_player_view` 类型。播放器对象由原生层管理，Flutter 只负责把这个视图放到布局中。

## 7. 弱网重连链路

```text
原生播放器发生 error/stalled
  → emit(error)
  → 1 秒后重试
  → 仍失败：2 秒后重试
  → 仍失败：4 秒后重试
  → 超过 3 次：emit(error)，交给上层展示失败状态
```

重连逻辑放在原生播放器附近，是因为只有原生播放器知道底层状态、当前 MediaItem 和真正的播放失败原因。Flutter 通过统一事件模型观察结果，不直接操作 ExoPlayer 或 AVPlayer。

## 8. FastAPI 请求链路

```text
HTTP/WebSocket 请求
  → api/v1/endpoints
  → Depends 注入数据库 Session / Service / 当前用户
  → Service 执行业务规则
  → Repository 访问 MySQL 或 Redis
  → Pydantic Schema 校验和序列化
  → ApiResponse 统一返回
```

HTTP 接口不直接把 SQL 写在路由函数里；WebSocket 也不传输视频二进制，只负责认证、弹幕和在线人数。视频流应该由专业媒体服务/CDN 分发，FastAPI 只保存房间元数据和控制面业务。

## 9. 新人推荐阅读顺序

1. `flutter_live_app/lib/main.dart`
2. `flutter_live_app/lib/app/router/app_router.dart`
3. `flutter_live_app/lib/features/home/presentation/pages/home_page.dart`
4. `flutter_live_app/lib/features/live/presentation/controllers/live_list_controller.dart`
5. `flutter_live_app/lib/core/network/api_client.dart`
6. `flutter_live_server/app/api/v1/endpoints/live.py`
7. `flutter_live_server/app/services/live_room_service.py`
8. `packages/flutter_live_core/lib/src/live_engine.dart`
9. `packages/flutter_live_media_plugin/lib/flutter_live_media_plugin.dart`
10. 当前平台对应的 Kotlin 或 Swift 文件

看懂这十个入口，就能顺着一条“页面 → 状态 → 网络/原生 → 返回页面”的完整路径继续阅读其他功能。
