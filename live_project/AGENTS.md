# 项目协作约定

本文件适用于 `live_project/` 正式源码根目录及其子目录。开始改动前，先阅读
`README.md`、`ARCHITECTURE.md`，以及与当前模块相邻的说明文件；若它们与用户的
最新明确要求冲突，以用户要求为准。

## 工作边界

- 正式源码位于当前目录；不要修改上一级的旧目录或 `duplicate_backup_*` 备份。
- 保留既有、无关的工作区改动；不要使用 `git reset --hard`、`git checkout --` 或批量删除来清理工作区。
- 不提交密钥、Token、真实用户数据、`.env` 或构建产物。新增配置项时同步更新 `.env.example`。
- 改动范围应尽量小。新增依赖须有明确收益，并同时更新依赖清单与锁文件。
- 不把尚未接入的推流、支付、礼物、审核或第三方服务描述为已真实可用；使用 Mock 或占位时必须明确标注边界。

## 架构红线

- Flutter 采用 feature-first：页面和 Widget 只负责展示与交互；状态和编排在 Controller；领域接口在 `domain`；Repository 负责数据来源选择；DataSource 负责 HTTP/WebSocket 等具体 I/O。
- 页面、Widget 和路由层不得直接调用 Dio、WebSocket、数据库或平台通道。
- 后端保持 `api → services → repositories → models` 分层：Endpoint 做鉴权、参数转换和 HTTP 响应；Service 放业务规则和事务编排；Repository 只做持久化读写。
- API 的请求/响应结构定义在 `app/schemas`；接口变更须同步更新客户端模型、调用方和测试。
- Flutter 与原生媒体能力只能通过 `flutter_live_core` 的 `LiveEngine` 抽象和 `flutter_live_media_plugin` 边界访问。修改 Pigeon 接口时使用既有生成流程，不手改 `*.g.dart`、`*.g.swift`、`*.g.kt` 等生成文件。
- 数据库结构变更必须新增 Alembic migration；不要只修改 SQLAlchemy Model。

## 验证基线

仅运行与改动相关且本机环境可执行的检查，并在交付时报告实际结果：

```bash
# Flutter 客户端
cd flutter_live_app && dart format . && flutter analyze && flutter test

# Python 服务端
cd flutter_live_server && ruff check . && pytest
```

媒体插件或原生代码有改动时，也应运行对应包的格式化、静态分析和测试；若受平台、服务或凭据限制无法执行，说明未执行的命令、原因和替代验证。

## 交付要求

交付说明应列出：改动文件、完成的行为、Mock/占位或遗留限制、验证命令及结果。不要凭空声称测试、构建或真机验证已经通过。
