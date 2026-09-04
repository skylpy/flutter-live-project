// HAR 的构建任务由 DevEco 的 hvigor-ohos-plugin 提供。
// DevEco 6.x 要求在 root hvigorfile 中声明 system plugin，旧版只导出
// harTasks 的写法会被识别为“没有 system plugin”。
// HAR 工程使用 DevEco 内置的 harTasks，Flutter 工具会在应用构建时消费
// 这个 HAR，并把 Index.ets 中导出的插件类注册到 Flutter Engine。
export { harTasks } from '@ohos/hvigor-ohos-plugin';
