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

  /// 真机验证播放器时可通过 dart-define 临时打开本地 Mock 数据。
  ///
  /// 默认值为 false，所以正式构建和普通开发仍然走真实 REST API。
  /// 只有明确传入 `--dart-define=USE_MOCK_LIVE_DATA=true` 才会启用，
  /// 这样局域网后端暂时不可达时，也能单独验证直播间和原生 HLS 播放链路。
  static const useMockLiveData = bool.fromEnvironment(
    'USE_MOCK_LIVE_DATA',
    defaultValue: false,
  );

  static String get websocketBaseUrl {
    // HTTP API 和 WebSocket 共用服务地址时，只需要替换协议为 ws/wss。
    if (apiBaseUrl.startsWith('https://')) {
      return apiBaseUrl.replaceFirst('https://', 'wss://');
    }
    return apiBaseUrl.replaceFirst('http://', 'ws://');
  }
}
