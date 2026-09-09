import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import '../../../../core/network/api_exception.dart';
import '../models/app_file.dart';
import '../repositories/file_repository.dart';

/// 独立的 OSS 传输客户端，不带 API 的 JWT、JSON 编码或 URL 日志拦截器。
class FileService {
  FileService(this.repository, {Dio? transferDio})
    : _dio =
          transferDio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(minutes: 10),
              receiveTimeout: const Duration(minutes: 10),
              followRedirects: false,
              responseType: ResponseType.plain,
            ),
          );
  final FileRepository repository;
  final Dio _dio;

  Future<AppFile> uploadFile({
    required File file,
    required String category,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    void Function(FileUploadState)? onState,
  }) => uploadSource(
    filename: file.uri.pathSegments.last,
    length: file.length,
    openRead: file.openRead,
    category: category,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    onState: onState,
  );

  Future<AppFile> uploadSource({
    required String filename,
    required Future<int> Function() length,
    required Stream<List<int>> Function() openRead,
    required String category,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    void Function(FileUploadState)? onState,
  }) async {
    try {
      onState?.call(const FileUploadState(phase: UploadPhase.preparing));
      _checkCancelled(cancelToken);
      final size = await length();
      final detectedType = lookupMimeType(filename);
      final contentType = detectedType == 'audio/x-wav'
          ? 'audio/wav'
          : detectedType;
      if (contentType == null) throw const FileTransferException('无法识别文件类型');
      final signature = await repository.getUploadSignature(
        filename: filename,
        contentType: contentType,
        category: category,
        fileSize: size,
        cancelToken: cancelToken,
      );
      _checkCancelled(cancelToken);
      if (signature.method != 'PUT') {
        throw const FileTransferException('不支持的上传方式');
      }
      onState?.call(const FileUploadState(phase: UploadPhase.uploading));
      await _dio.put<Object?>(
        signature.uploadUrl,
        data: openRead(),
        cancelToken: cancelToken,
        options: Options(headers: signature.headers),
        onSendProgress: (sent, total) {
          onSendProgress?.call(sent, total);
          onState?.call(
            FileUploadState(
              phase: UploadPhase.uploading,
              progress: total > 0 ? (sent / total).clamp(0, 1) : 0,
            ),
          );
        },
      );
      // 上传期间取消，或上传成功后取消，都不再发完成确认请求。
      _checkCancelled(cancelToken);
      onState?.call(
        const FileUploadState(phase: UploadPhase.confirming, progress: 1),
      );
      final result = await repository.completeUpload(
        signature: signature,
        filename: filename,
        contentType: contentType,
        fileSize: size,
        cancelToken: cancelToken,
      );
      onState?.call(
        FileUploadState(phase: UploadPhase.success, progress: 1, file: result),
      );
      return result;
    } catch (error) {
      final message = cancelToken?.isCancelled == true
          ? '上传已取消'
          : fileErrorMessage(error);
      onState?.call(
        FileUploadState(phase: UploadPhase.failed, errorMessage: message),
      );
      throw FileTransferException(message);
    }
  }

  Future<String> getDownloadUrl(int fileId) =>
      repository.getDownloadUrl(fileId);

  Future<File> downloadFile({
    required int fileId,
    required String savePath,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        _checkCancelled(cancelToken);
        final url = await repository.getDownloadUrl(
          fileId,
          cancelToken: cancelToken,
        );
        try {
          await _dio.download(
            url,
            savePath,
            cancelToken: cancelToken,
            onReceiveProgress: onProgress,
            deleteOnError: true,
          );
          return File(savePath);
        } on DioException catch (error) {
          if (error.response?.statusCode != 403 || attempt == 1) rethrow;
          // 仅 OSS 的 403 重取一次签名；后端权限失败不会进入该重试。
        }
      }
      throw const FileTransferException('下载失败');
    } catch (error) {
      throw FileTransferException(
        cancelToken?.isCancelled == true ? '下载已取消' : fileErrorMessage(error),
      );
    }
  }

  Future<void> deleteFile(int fileId) => repository.deleteFile(fileId);
  void dispose() => _dio.close(force: true);

  void _checkCancelled(CancelToken? token) {
    if (token?.isCancelled == true) throw token!.cancelError!;
  }
}

String fileErrorMessage(Object error) {
  if (error is FileTransferException) return error.message;
  if (error is ApiException) {
    if (error.statusCode == 503) return '文件服务未就绪，请检查后端 OSS 配置';
    if (error.statusCode == 413) return '文件超过大小限制';
    return error.message;
  }
  if (error is DioException) {
    if (CancelToken.isCancel(error)) return '传输已取消';
    if (error.response?.statusCode == 403) return 'OSS 签名已过期或权限不足，请重试';
    if (error.response?.statusCode == 409) return '该上传地址已使用，请重新选择文件';
    return '文件传输失败，请检查网络后重试';
  }
  return '文件操作失败，请重试';
}
