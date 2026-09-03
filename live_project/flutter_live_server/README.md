# flutter_live_server

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
- Swagger：`/docs`

第二阶段已启用 JWT 认证、Redis 在线人数和基础 WebSocket 弹幕；消息暂不持久化。直播列表和详情接口需要 MySQL 已启动且已完成迁移和 Seed，WebSocket 在线人数需要 Redis。
