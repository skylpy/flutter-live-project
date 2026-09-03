# Flutter Live 第一阶段

前后端分离的跨平台直播 App 基础项目：

```text
live_project/
├── flutter_live_app/     # Flutter / Riverpod / go_router / Dio
└── flutter_live_server/  # FastAPI / SQLAlchemy / MySQL / Alembic
```

当前已完成第一阶段 REST 闭环，并开始第二阶段认证与实时基础能力；播放器、推流、拉流和原生插件仍未实现。

## 后端快速开始

后端要求 Python 3.11+、MySQL 8+。在 `flutter_live_server` 目录执行：

```bash
python -m venv .venv
source .venv/bin/activate                 # macOS/Linux
# .venv\Scripts\activate                  # Windows
pip install -r requirements.txt
cp .env.example .env
```

编辑 `.env` 中的 MySQL 连接配置，然后创建数据库：

```sql
CREATE DATABASE flutter_live
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

执行迁移、插入幂等 Seed 数据并启动：

```bash
alembic upgrade head
python -m app.scripts.seed_live_rooms
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

验证接口：

```bash
curl http://localhost:8000/api/v1/health
curl http://localhost:8000/api/v1/live/rooms
```

Swagger 地址：<http://localhost:8000/docs>。

## Flutter 快速开始

```bash
cd flutter_live_app
flutter pub get
dart format .
flutter run
```

默认 API 地址是 `http://localhost:8000/api/v1`。Android Emulator 使用：

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

iOS Simulator / macOS 可使用默认的 `localhost`；真机和 HarmonyOS 真机应将 `API_BASE_URL` 设置为开发电脑局域网 IP，例如 `http://192.168.1.10:8000/api/v1`。

## 已实现

- Flutter Material 3、ProviderScope、Riverpod AsyncNotifier、go_router StatefulShellRoute
- 五个底部 Tab，Tab 分支导航状态保留，重复点击回到分支初始位置
- 首页通过 `GET /api/v1/live/rooms` 加载两列直播卡片
- Loading、Error、Retry、RefreshIndicator
- 点击房间后通过 roomId 请求详情，并由 root navigator 打开全屏黑色直播间占位页
- FastAPI 统一响应、错误处理、CORS、SQLAlchemy 2.x Repository / Service 分层
- MySQL `live_rooms` 表、Alembic 初始迁移、可重复执行的四条 Seed 数据
- 第二阶段：用户注册/登录、JWT、Redis 在线人数、带 JWT 的直播间 WebSocket 弹幕

## 暂未实现

礼物、推流、拉流、RTMP、HTTP-FLV、HLS、WebRTC、播放器、PlatformView、Pigeon、Swift、Kotlin、ArkTS、HarmonyOS、连麦、PK、AI 审核和直播摘要。

## 第二阶段建议

下一步可完善认证 UI、在线人数展示和消息历史，再设计独立的 `flutter_live_core` / `LiveEngine` 接口以及原生播放器和推流插件；媒体分发应由专业媒体服务/CDN 承担，不经过 FastAPI 转发视频二进制流。
