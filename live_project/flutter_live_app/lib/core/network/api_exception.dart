/// 客户端统一使用的可预期业务异常。
///
/// 页面只处理这个类型，不需要了解 DioException 的内部结构。
class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final int? code;

  @override
  String toString() => message;
}
