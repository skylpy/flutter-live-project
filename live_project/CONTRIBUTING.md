# 贡献指南

感谢为 Flutter Live 项目提交改动。本指南适用于客户端、FastAPI 服务端、媒体插件和部署配置。

## 开始前

1. 从本目录打开项目，并先阅读 `README.md`、`ARCHITECTURE.md` 和 `AGENTS.md`。
2. 先执行 `git status`，确认不覆盖他人的未提交改动。
3. 一个改动聚焦一个目标；功能、重构和格式化尽量不要混在同一提交中。
4. 涉及接口、数据库或原生通信的改动，先确认所有调用方与兼容策略。

## 开发流程

1. 从现有模块中找到最接近的实现，沿用命名、目录和依赖方向。
2. 先添加或更新测试，再实现行为；至少覆盖成功路径和一个失败、空数据或未登录路径。
3. 保持 UI、Controller、Repository、DataSource 和后端分层，不跨层访问 I/O。
4. 对 API、数据模型、环境变量、迁移或生成代码的改动，同步更新相关文档、示例和调用方。
5. 提交前完成与改动相关的格式化、静态检查和测试。

## 本地检查

```bash
# Flutter App
cd flutter_live_app
dart format .
flutter analyze
flutter test

# FastAPI 服务端
cd ../flutter_live_server
ruff check .
pytest
```

若只改动 `packages/`，请在对应包目录运行 `dart format .`、`flutter analyze` 和测试。原生平台构建只在具备相应 SDK 的环境中运行；未运行时须在变更说明中注明。

## 提交与评审

- 提交信息使用祈使句并说明范围，例如：`feat(live): add chat reconnect state`、`fix(auth): handle expired token`。
- PR/变更说明应包含目的、主要改动、验证结果、数据迁移或配置影响，以及截图或录屏（涉及界面时）。
- 不提交 `.env`、私钥、访问令牌、用户数据、`build/`、IDE 临时文件或无关格式化。
- 不要修改自动生成文件；如需变更 Pigeon 或数据库，请提交源定义和由正规流程生成的必要产物/迁移。

## 需要重点评审的改动

鉴权、权限、媒体生命周期、WebSocket 重连、文件上传、数据库迁移和删除操作必须说明失败处理、资源释放、回滚或兼容方案。涉及真实支付、推流或第三方账号时，先确认服务端接口与安全方案，不以客户端 Mock 替代真实能力。
