# 编码风格指南

项目以现有代码和工具配置为最终格式依据：Flutter 使用 `flutter_lints`，服务端使用
Ruff（行宽 100）。本指南补充跨模块的一致性规则。

## 通用

- 命名表达业务意图，避免 `data`、`handle`、`utils` 等没有语境的泛名。
- 一个函数只承担一个清晰职责；复杂分支拆为具名私有函数或对象。
- 注释说明“为什么”或资源/状态约束，不复述代码本身。对外 API、复杂状态机和平台差异应补充文档。
- 错误不得被静默吞掉。保留可诊断上下文，同时不要记录密码、Token 或敏感个人信息。
- 字符串、超时、分页大小和状态值应有语义化定义，避免散落的魔法值。

## Flutter / Dart

- 文件名使用 `snake_case.dart`；类型、Widget、Provider 使用 `UpperCamelCase`；变量、方法和参数使用 `lowerCamelCase`。
- 业务代码按 `features/<feature>/{data,domain,presentation}` 组织；可复用 UI 放 `shared`，跨业务基础设施放 `core`。
- Widget 尽量保持无状态；可观察的异步业务状态交给 Riverpod Controller/Provider 管理。UI 至少清晰处理 loading、error、empty 和可重试状态（适用时）。
- 使用 `const`、不可变模型和小型 Widget 以降低不必要重建；不要在 `build` 内启动网络请求、订阅或创建长期资源。
- `TextEditingController`、`AnimationController`、流订阅、播放器和 WebSocket 必须在生命周期中明确释放。
- 路由使用既有 `go_router` 配置；页面跳转不拼接未校验的字符串。UI 文案优先集中在功能模块，避免复制粘贴。
- 网络结果通过 DataSource/Repository 转换为领域模型或受控错误；不要把 Dio、平台异常或 JSON 细节泄露到页面。

## Python / FastAPI

- 文件、模块、函数和变量使用 `snake_case`；类、Pydantic Schema、SQLAlchemy Model 使用 `PascalCase`；常量使用 `UPPER_SNAKE_CASE`。
- Endpoint 保持薄：使用 Pydantic Schema 校验输入输出，通过依赖注入取得鉴权和数据库会话，并将业务规则交给 Service。
- Service 负责业务规则、权限判断和事务边界；Repository 不返回 HTTP 响应、不抛出 `HTTPException`。
- 对外错误使用项目统一异常/响应格式，避免把堆栈、数据库异常或内部配置返回给客户端。
- 数据库查询避免 N+1；写操作考虑幂等性、并发和失败回滚。变更结构时提供可升级的 Alembic migration。
- 异步函数只用于真正的异步 I/O；不要在 `async` Endpoint 内执行长时间阻塞任务。

## 媒体插件与平台代码

- 跨平台公共语义先定义在 `flutter_live_core`，再由媒体插件实现；接口应表达能力和状态，而非泄露某个平台播放器细节。
- 平台视图、播放器、回调和通道的创建与销毁必须成对；切换房间、页面销毁和异常路径均需释放资源。
- Pigeon 定义是唯一源头。重新生成后只审阅生成结果，不手工修补生成文件。
- iOS/macOS、Android 与 OpenHarmony 的行为差异需在实现旁说明，并提供不支持平台的安全降级。

## 格式化与例外

提交前执行对应格式化和检查。若必须忽略 lint，优先局部忽略并写明理由；不要为了单个历史问题降低全项目规则。任何与本指南冲突的已配置 lint 规则，以工具实际输出为准。
