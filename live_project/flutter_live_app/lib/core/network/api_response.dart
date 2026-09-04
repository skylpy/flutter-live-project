/// 后端 HTTP 接口统一使用的响应外壳。
///
/// [T] 是 data 的真实业务类型，例如 `List<LiveRoom>` 或 `AuthSession`。
class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final T data;

  factory ApiResponse.fromJson(
    Map<String, Object?> json,
    T Function(Object? value) parseData,
  ) {
    // 只在这一层读取 code/message/data，具体模型只解析自己的 data。
    return ApiResponse<T>(
      code: _asInt(json['code']),
      message: json['message'] as String? ?? '',
      data: parseData(json['data']),
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? -1;
}
