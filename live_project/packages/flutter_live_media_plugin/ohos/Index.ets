import FlutterLiveMediaPlugin from './src/main/ets/components/plugin/FlutterLiveMediaPlugin';

// Flutter 工具通过 Index.ets 找到插件的默认导出类，并把它注册到 Flutter
// Engine。业务工程不需要手动复制播放器实现，只需要依赖这个 HAR 插件。
export default FlutterLiveMediaPlugin;
