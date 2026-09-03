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
    return ApiResponse<T>(
      code: _asInt(json['code']),
      message: json['message'] as String? ?? '',
      data: parseData(json['data']),
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? -1;
}
