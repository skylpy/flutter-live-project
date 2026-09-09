import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../models/app_file.dart';

class FileRepository {
  FileRepository(this.api);
  final ApiClient api;

  Future<UploadSignature> getUploadSignature({
    required String filename,
    required String contentType,
    required String category,
    required int fileSize,
    CancelToken? cancelToken,
  }) async {
    final result = await api.post<UploadSignature>(
      '/files/upload-signature',
      data: {
        'filename': filename,
        'content_type': contentType,
        'category': category,
        'file_size': fileSize,
      },
      cancelToken: cancelToken,
      parseData: UploadSignature.fromJson,
    );
    return result.data;
  }

  Future<AppFile> completeUpload({
    required UploadSignature signature,
    required String filename,
    required String contentType,
    required int fileSize,
    CancelToken? cancelToken,
  }) async {
    final result = await api.post<AppFile>(
      '/files/upload-complete',
      data: {
        'object_key': signature.objectKey,
        'original_filename': filename,
        'content_type': contentType,
        'file_size': fileSize,
      },
      cancelToken: cancelToken,
      parseData: AppFile.fromJson,
    );
    return result.data;
  }

  Future<List<AppFile>> listFiles({int? beforeId}) async {
    final result = await api.get<List<AppFile>>(
      '/files?limit=30${beforeId == null ? '' : '&before_id=$beforeId'}',
      parseData: (value) => (value as List).map(AppFile.fromJson).toList(),
    );
    return result.data;
  }

  Future<AppFile> getFile(int id) async =>
      (await api.get<AppFile>('/files/$id', parseData: AppFile.fromJson)).data;

  Future<String> getDownloadUrl(int fileId, {CancelToken? cancelToken}) async =>
      (await api.get<String>(
        '/files/$fileId/download-url',
        cancelToken: cancelToken,
        parseData: (value) => (value as Map)['url'] as String,
      )).data;

  Future<void> deleteFile(int id) => api.delete('/files/$id');
}
