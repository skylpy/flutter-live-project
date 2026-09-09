import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/models/app_file.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/services/file_service.dart';

final fileRepositoryProvider = Provider(
  (ref) => FileRepository(ref.watch(apiClientProvider)),
);
final fileServiceProvider = Provider.autoDispose((ref) {
  final service = FileService(ref.watch(fileRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});
final fileUploadControllerProvider =
    NotifierProvider.autoDispose<FileUploadController, FileUploadState>(
      FileUploadController.new,
    );

class FileUploadController extends Notifier<FileUploadState> {
  CancelToken? _token;
  @override
  FileUploadState build() {
    ref.watch(fileServiceProvider);
    ref.onDispose(() => _token?.cancel());
    return const FileUploadState();
  }

  Future<AppFile?> upload(PlatformFile file, String category) async {
    return _uploadSource(
      filename: file.name,
      length: file.length,
      openRead: file.readAsByteStream,
      category: category,
    );
  }

  /// 动态发布来自系统相册的 [XFile]，使用相同的安全直传链路。
  Future<AppFile?> uploadXFile(XFile file, String category) async {
    return _uploadSource(
      filename: file.name,
      length: file.length,
      openRead: file.openRead,
      category: category,
    );
  }

  Future<AppFile?> _uploadSource({
    required String filename,
    required Future<int> Function() length,
    required Stream<List<int>> Function() openRead,
    required String category,
  }) async {
    if (state.busy) return null;
    final token = CancelToken();
    _token = token;
    try {
      return await ref
          .read(fileServiceProvider)
          .uploadSource(
            filename: filename,
            length: length,
            openRead: openRead,
            category: category,
            cancelToken: token,
            onState: (value) {
              if (ref.mounted) state = value;
            },
          );
    } on FileTransferException {
      return null;
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  Future<void> cancelUpload() async => _token?.cancel('用户取消');
}
