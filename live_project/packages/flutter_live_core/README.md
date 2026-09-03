# flutter_live_core

跨平台直播媒体引擎的 Flutter 侧协议包。

当前只提供平台无关的 `LiveEngine` 接口、事件模型和 `StubLiveEngine`，不会打开摄像头、不会播放或推送真实媒体流。后续可以在 Flutter Plugin 中分别实现 iOS Swift、Android Kotlin 和 HarmonyOS / OpenHarmony ArkTS 适配层。

建议依赖方向：

```text
业务 Feature -> flutter_live_core -> 平台 Plugin -> 原生播放器 / 推流 SDK
```

PlatformView、MethodChannel、Pigeon 和真实媒体 SDK 将在后续阶段按平台逐步加入。
