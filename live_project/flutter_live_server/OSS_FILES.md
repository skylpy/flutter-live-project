# OSS 文件系统

## 密钥在哪里填写

本地 FastAPI：本目录的 `.env`（与 `requirements.txt` 同级），已创建空值占位并被 Git 忽略。

```env
OSS_REGION=oss-cn-shenzhen
OSS_ENDPOINT=https://oss-cn-shenzhen.aliyuncs.com
OSS_BUCKET=doc-converter-pdf
OSS_PDF_DIR=pdf
OSS_RESULT_DIR=result
OSS_SOURCE_DIR=source
OSS_SIGN_EXPIRE=900
OSS_USE_SIGNED_URL=true
OSS_ACCESS_KEY_ID=填入你的AccessKeyId
OSS_ACCESS_KEY_SECRET=填入你的AccessKeySecret
```

严禁把 OSS_ACCESS_KEY_SECRET 放入 Flutter。不要通过聊天、Git、截图或日志分享真实密钥。
部署 Docker Compose 时填 `../deploy/.env`，它由 Compose 的 `env_file` 注入 FastAPI。
实际进程环境变量优先于 dotenv；同时兼容工作目录中的 `.env`。修改后必须重启后端。
缺少关键配置时启动日志列出缺失变量，文件签名接口返回统一 503；其他业务接口继续启动。

使用私有 Bucket，RAM 用户权限限于 `doc-converter-pdf/flutter/*` 的 GetObject、PutObject、DeleteObject。
无需给 Flutter 任何 RAM 密钥或删除权限。不改变 Bucket ACL，不依赖公共读。
`OSS_USE_SIGNED_URL=false` 仅适合已经由运维配置为公共可读的资源，私有 Bucket 保持 true。

SDK Signed URL 必须带凭证标识（V4 的 `x-oss-credential` 包含 AccessKey ID）；这是 OSS 协议要求。
API 不单独返回 AK/SK 字段，绝不返回 Secret，URL 不提供生成新签名的能力。
签名 URL 本身在有效期内具有访问权限，后端日志只记录操作和 key，Flutter OSS Dio 无日志拦截器。

## 接口与调用流程

所有接口要求现有 JWT `Authorization: Bearer …`，响应沿用 `{code,message,data}`；文件接口字段使用 snake_case。

| 接口 | 行为 |
| --- | --- |
| `POST /api/v1/files/upload-signature` | 验证分类、文件名、扩展名、MIME 和大小；生成 UUID key、900 秒 PUT 签名，记录 processing 上传意向 |
| `POST /api/v1/files/upload-complete` | 校验签发记录、归属和 OSS object_exists/HEAD；实际大小和类型一致后变 active；可重复确认 |
| `GET /api/v1/files?limit=30&before_id=123` | 仅列出本人的 active 文件，按 ID 倒序分页；不签发或保存 URL |
| `GET /api/v1/files/{id}` | 本人文件信息及即时展示 URL |
| `GET /api/v1/files/{id}/download-url` | 本人文件的即时下载 URL，签名携带原始下载文件名 |
| `DELETE /api/v1/files/{id}` | 先校验归属，再删除 OSS 对象、软删除数据库记录；重复删除成功 |

上传：UI → FileUploadController → FileService → FileRepository → FastAPI 获取签名 → 独立 Dio 流式 PUT 到 OSS → FastAPI 确认 → AppFile。
PUT 必须原样携带返回的 headers，不附带 App JWT。Content-Type、Content-Length 和 `x-oss-forbid-overwrite:true` 纳入签名，避免改大小、类型或重复覆盖已确认内容。
上传进度为 0～1；状态：idle、preparing、uploading、confirming、success、failed；可取消，确认请求发出前取消不调用 upload-complete。
确认请求已到达服务器时取消不能撤销已提交的事务；重新加载列表可恢复记录。

发布动态：发布页选择最多 9 张图片或 1 个视频 → 复用上述直传链路取得 active 文件 ID → `POST /api/v1/feed/posts` 仅提交 `body` 和 `file_ids` → 后端校验文件归属、状态和媒体类型 → 写入动态与 `feed_post_media` 关联 → 刷新动态列表。读取动态时后端为每个关联媒体即时签发 URL，URL 不写库；已用于动态的文件不能在“我的文件”中单独删除。

下载：FileRepository 请求新 URL → 独立 Dio.download 写入文件，支持进度、超时和 CancelToken。
仅 OSS 返回 403 时刷新签名后重试一次，后端的权限错误不重试。失败删除部分下载文件。
页面下载到 App 文档目录的独立 downloads 子目录，显示保存路径；不覆盖已有文件。

删除：Flutter 请求后端 → 验证 owner → OSS 删除成功 → status=deleted、deleted_at 写入数据库 → UI 移除。
删除失败保留 active 记录，以便重试。已删除记录不能通过旧完成请求重新激活。

key 默认 `flutter/{category}/{userId}/{yyyyMMdd}/{uuid}.{extension}`；source/pdf/result 的目录名可通过对应配置替换。
目录配置只允许字母、数字、下划线和连字符。客户端无法指定 key、用户目录或完整路径。

大小上限：avatar 10 MiB、image 20 MiB、pdf/document 50 MiB、audio 100 MiB、video/source/result 500 MiB。
可用 `OSS_MAX_SIZES` JSON 配置所有分类上限，参见 `.env.example`。
source/result 仍受支持的扩展名/MIME 白名单限制；不允许任意二进制或 HTML/SVG 可执行内容。
扩展名和声明 MIME 校验不等同于杀毒或文件内容审核，HEAD 校验也不能证明字节内容的真实格式。

## 数据库及启动

迁移 `0007_file_records` 增加 `file_records`，含 id、user_id、object_key 唯一约束、原文件名、MIME、大小、分类、状态和时间戳。
只保存 key 和元数据，不保存 signed URL。签发时先建 processing 记录，以便校验完成请求和后续孤儿清理。

```bash
# 在 flutter_live_server 目录执行；建议 Python 3.11+ / OpenSSL 环境。
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Compose 部署先更新 `deploy/.env`，再 `docker compose up -d --build api`；按部署流程执行 `docker compose exec api alembic upgrade head`。

## Swagger / curl 验收

打开 `/docs`，通过现有登录接口获取 Token，再点 Authorize。
签名接口请求示例：

```json
{"filename":"test.jpg","content_type":"image/jpeg","category":"image","file_size":102400}
```

文件大小必须与本地实际字节数一致。签名生成本身不请求 OSS，只有实际 PUT 成功才算云端权限和配置验收通过。
把返回值保留在本地临时变量中（不要发布完整 URL），执行：

```bash
curl --fail --request PUT "$UPLOAD_URL" \
  --header 'Content-Type: image/jpeg' \
  --header "Content-Length: $FILE_SIZE" \
  --header 'x-oss-forbid-overwrite: true' \
  --data-binary @test.jpg
```

在 Swagger 调 upload-complete，填 object_key 和签名时相同的原始文件信息。
再依次调用文件详情、download-url（用返回 URL 直接 GET OSS）和 DELETE；重复 DELETE 应成功。
另一个账户访问应 403，未登录 401、不存在 404、参数错误 400/422、过大 413、OSS 故障 502。

浏览器/Web 直传时还需要运维在 Bucket 配置准确的应用来源 CORS：允许 PUT/GET/HEAD，允许 Content-Type、x-oss-forbid-overwrite（或请求头 `*`），暴露 ETag。
本轮文件页面面向 Android/iOS/桌面原生，下载使用 dart:io；Web 文件保存和展示完整验收尚未实现。
macOS 沙盒若启用，需要按文件选择器文档配置 user-selected 文件访问权限。

## Flutter 入口与类

入口：登录 → 我的 → 我的文件（路由 `/files`），选择分类 → 选择文件并上传 → 查看/下载/删除。
支持 Android 内容 URI，使用 PlatformFile 字节流读取，不依赖实际文件路径，不把大视频整体读入内存。

- `features/files/data/models/app_file.dart`：UploadSignature、AppFile、UploadPhase、FileUploadState、FileTransferException。
- `features/files/data/repositories/file_repository.dart`：签名、确认、列表、详情、下载 URL、删除，复用 API JWT/401 行为。
- `features/files/data/services/file_service.dart`：FileService 直传、下载、取消、一次签名过期重试，独立 Dio 隔离凭证。
- `features/files/presentation/controllers/file_controller.dart`：Riverpod 上传状态和取消。
- `features/files/presentation/pages/files_page.dart`：最小文件管理页面。

## 测试及待验收

本轮新增后端文件：`app/api/v1/endpoints/files.py`、`app/models/file.py`、`app/schemas/file.py`、
`app/services/file_service.py`、`app/services/oss_service.py`、`app/utils/file_utils.py`、`app/utils/__init__.py`、
`alembic/versions/0007_file_records.py`、`tests/test_files.py`、本说明和忽略版本控制的 `.env`。
修改后端配置 `app/core/config.py`、启动检查 `app/main.py`、路由 `app/api/v1/router.py`、模型注册 `alembic/env.py`、
`requirements.txt`、`.env.example`、`README.md` 和 `../deploy/.env.example`。

Flutter 新增上列 5 个业务文件及 `test/file_service_test.dart`；修改 `lib/core/network/api_client.dart`
（GET/POST 取消参数和 DELETE）、`lib/app/router/app_router.dart`、`features/profile/presentation/pages/profile_page.dart`、
`pubspec.yaml`/`pubspec.lock`、README，依赖安装同时更新桌面插件自动注册文件。
新增依赖 `oss2`、`file_picker`、`mime`、`path_provider`，保持 Dio/Riverpod 架构。

```bash
# 后端
.venv/bin/python -m pytest -q
# Flutter app 目录
flutter analyze
flutter test
flutter build apk --debug
```

后端测试用隔离数据库和 OSS 替身验证权限、元数据、幂等与异常，另用真实 oss2 验证离线签名格式。
Flutter 测试用本地 HTTP 服务验证实际二进制 PUT/GET、进度、Token 隔离、取消及 403 有界重试。
这些自动化测试不等于设备端 UI 验收；填写有效密钥后仍应按上述入口验证 Android/iOS 文件页面。

本轮执行结果（2026-09-08）：本地 MySQL 已迁移至 `0007_file_records`；后端 25 项测试通过；Flutter 11 项测试通过；
`flutter analyze` 无问题；Android debug APK 构建成功；本轮后端文件 Ruff 检查通过。
后端全项目 Ruff 尚有 11 项原有问题（social 模块的 UTC 时间调用、导入排序以及 media_server_client 未使用导入），未扩展修改范围。
当前本地 Python 3.9/LibreSSL 环境产生 urllib3 TLS 兼容警告，生产/云端验收建议使用项目要求的 Python 3.11+ OpenSSL 环境。
真实 OSS 验证（2026-09-08）已在本地 `.env` 的有效配置下通过：签名、客户端直传 PUT（200）、后端 `object_exists`/HEAD 确认、文件列表、签名下载 GET（200，字节一致）及删除均成功。发布动态闭环亦已验证：媒体上传确认、创建动态、签名媒体读取（200，字节一致）成功；临时动态与 OSS 对象已清理。数据库仅保留文件软删除审计记录；测试过程没有输出密钥、令牌或完整签名 URL。Android/iOS 文件页面和发布页的设备验收尚未完成。

TODO：`OSSService.cleanup_orphan_objects()` 预留定时清理接口，本阶段未调度。未来按 processing 记录及签名到期时间清理未确认对象；删除后旧签名到期前重传也可能产生孤儿，需一并处理。
断点续传、配额/频率限制、文件内容审核、Web 保存、与头像/动态附件的业务关联可按后续需求增加。
