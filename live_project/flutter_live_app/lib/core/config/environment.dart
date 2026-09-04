/// 读取编译时环境配置。
///
/// 通过 `--dart-define=API_BASE_URL=...` 切换开发、测试和生产地址，避免把
/// 环境差异散落在业务页面中。
class Environment {
  const Environment._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  static String get websocketBaseUrl {
    // HTTP API 和 WebSocket 共用服务地址时，只需要替换协议为 ws/wss。
    if (apiBaseUrl.startsWith('https://')) {
      return apiBaseUrl.replaceFirst('https://', 'wss://');
    }
    return apiBaseUrl.replaceFirst('http://', 'ws://');
  }
}
