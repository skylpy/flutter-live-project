# Flutter Live 项目仓库

正式项目目录只有一个：[`live_project/`](live_project/)。

请从下面的目录打开 Android Studio、执行 Flutter 命令或启动后端：

```text
live_project/
├── flutter_live_app/       # Flutter 客户端
├── flutter_live_server/    # FastAPI 后端
├── media_server/           # SRS / RTMP / HLS 配置
├── packages/               # Flutter 跨平台核心和原生媒体插件
├── deploy/                 # Docker Compose 部署文件
└── docs/                   # 需求和实现说明
```

外层仓库根目录只负责 Git 管理，不再放置第二份 `flutter_live_app`、
`flutter_live_server`、`media_server` 或 `packages`。详细的新人阅读指南请看
[`live_project/ARCHITECTURE.md`](live_project/ARCHITECTURE.md)，快速启动说明请看
[`live_project/README.md`](live_project/README.md)。
