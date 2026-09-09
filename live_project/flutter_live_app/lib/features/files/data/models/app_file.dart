class UploadSignature {
  const UploadSignature({
    required this.objectKey,
    required this.uploadUrl,
    required this.method,
    required this.headers,
    required this.expire,
  });
  final String objectKey;
  final String uploadUrl;
  final String method;
  final Map<String, String> headers;
  final int expire;

  factory UploadSignature.fromJson(Object? value) {
    final json = Map<String, dynamic>.from(value as Map);
    return UploadSignature(
      objectKey: json['object_key'] as String,
      uploadUrl: json['upload_url'] as String,
      method: json['method'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      expire: json['expire'] as int,
    );
  }
}

class AppFile {
  const AppFile({
    required this.id,
    required this.objectKey,
    required this.originalFilename,
    required this.contentType,
    required this.fileSize,
    required this.category,
    required this.createdAt,
    this.url,
  });
  final int id;
  final String objectKey;
  final String originalFilename;
  final String contentType;
  final int fileSize;
  final String category;
  final DateTime createdAt;
  // 只在当前页面内存中使用；签名 URL 不写入本地存储。
  final String? url;

  factory AppFile.fromJson(Object? value) {
    final json = Map<String, dynamic>.from(value as Map);
    return AppFile(
      id: json['id'] as int,
      objectKey: json['object_key'] as String,
      originalFilename: json['original_filename'] as String,
      contentType: json['content_type'] as String,
      fileSize: json['file_size'] as int,
      category: json['category'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      url: json['url'] as String?,
    );
  }
}

enum UploadPhase { idle, preparing, uploading, confirming, success, failed }

class FileUploadState {
  const FileUploadState({
    this.phase = UploadPhase.idle,
    this.progress = 0,
    this.errorMessage,
    this.file,
  });
  final UploadPhase phase;
  final double progress;
  final String? errorMessage;
  final AppFile? file;
  bool get busy =>
      phase == UploadPhase.preparing ||
      phase == UploadPhase.uploading ||
      phase == UploadPhase.confirming;
}

class FileTransferException implements Exception {
  const FileTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}
