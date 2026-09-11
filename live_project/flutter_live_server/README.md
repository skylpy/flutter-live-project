# flutter_live_server

建议先阅读项目根目录的 [ARCHITECTURE.md](../ARCHITECTURE.md)。服务端的基本链路是：Endpoint → Service → Repository → MySQL/Redis，Pydantic Schema 负责输入校验和输出格式。

`/live/ws/rooms/{room_id}` 只承载认证、弹幕和在线人数，不传输视频二进制；视频应由专业媒体服务/CDN 分发。

FastAPI 直播后端第二阶段，使用 SQLAlchemy 2.x + MySQL 8 + Alembic + Redis。要求 Python 3.11+。

```bash
python -m venv .venv
source .venv/bin/activate                 # macOS/Linux
# .venv\Scripts\activate                  # Windows
pip install -r requirements.txt
cp .env.example .env
```

在 MySQL 中创建数据库：

```sql
CREATE DATABASE flutter_live CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

配置 `.env` 后执行：

```bash
alembic upgrade head
python -m app.scripts.seed_live_rooms
python -m app.scripts.seed_virtual_residents
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

接口：

- `GET /api/v1/health`
- `GET /api/v1/live/rooms`
- `GET /api/v1/live/rooms/{room_id}`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`（Bearer JWT）
- `WS /api/v1/live/ws/rooms/{room_id}?token=...`
- `WS /api/v1/ws/notifications?token=...`
- Swagger：`/docs`

实时通道说明：房间 WebSocket 负责弹幕和在线人数；用户通知 WebSocket 负责私信、关注、点赞和全部已读事件。两条连接都使用 JWT 查询参数，客户端断线后自动指数退避重连。历史通知和消息仍以 MySQL REST 接口为准，Redis 不可用时服务端会退回当前进程内广播。

## 虚拟居民与 DeepSeek

执行迁移和 `python -m app.scripts.seed_virtual_residents` 后，会创建一组标识为“虚拟”的社区角色及其初始文字动态。把 `DEEPSEEK_API_KEY` 填入本目录 `.env`，再重启 FastAPI，直播间会在真人进房或发言时由房间导演低频触发角色回应；没有密钥时不会发起任何模型请求，也不会影响正常弹幕。

密钥只允许保存在服务端环境变量或 `.env`，不能提交到 Git，不能写入 Flutter 的 `--dart-define`、App 配置或客户端日志。虚拟居民消息会带 `isVirtual` 字段，客户端会展示其身份。

## OSS 文件上传、下载与删除

已接入 `/api/v1/files`；配置密钥、数据库迁移、Swagger/curl 验收、Flutter 入口和 TODO 见 [OSS_FILES.md](OSS_FILES.md)。
本地密钥填写本目录 `.env` 的 `OSS_ACCESS_KEY_ID` 和 `OSS_ACCESS_KEY_SECRET`，修改后重启 FastAPI。禁止放入 Flutter。
