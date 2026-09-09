import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_app/features/files/data/models/app_file.dart';
import 'package:flutter_live_app/features/files/data/repositories/file_repository.dart';
import 'package:flutter_live_app/features/files/data/services/file_service.dart';

class TestRepository implements FileRepository {
  String url = '';
  int confirms = 0;
  int downloadSigns = 0;
  final calls = <String>[];
  final record = AppFile(
    id: 1,
    objectKey: 'issued-key',
    originalFilename: 'photo.jpg',
    contentType: 'image/jpeg',
    fileSize: 4,
    category: 'image',
    createdAt: DateTime(2026),
  );

  @override
  Future<UploadSignature> getUploadSignature({
    required String filename,
    required String contentType,
    required String category,
    required int fileSize,
    CancelToken? cancelToken,
  }) async {
    calls.add('sign');
    expect(filename, 'photo.jpg');
    expect(contentType, 'image/jpeg');
    return UploadSignature(
      objectKey: 'issued-key',
      uploadUrl: url,
      method: 'PUT',
      headers: {
        'Content-Type': contentType,
        'Content-Length': '$fileSize',
        'x-oss-forbid-overwrite': 'true',
      },
      expire: 900,
    );
  }

  @override
  Future<AppFile> completeUpload({
    required UploadSignature signature,
    required String filename,
    required String contentType,
    required int fileSize,
    CancelToken? cancelToken,
  }) async {
    calls.add('complete');
    confirms++;
    expect(signature.objectKey, 'issued-key');
    return record;
  }

  @override
  Future<String> getDownloadUrl(int fileId, {CancelToken? cancelToken}) async {
    downloadSigns++;
    return url;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late HttpServer server;
  late Directory temp;
  late TestRepository repository;
  late FileService service;
  late File file;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    temp = await Directory.systemTemp.createTemp('oss-transfer-test-');
    file = await File('${temp.path}/photo.jpg').writeAsBytes([1, 2, 3, 4]);
    repository = TestRepository()
      ..url = 'http://127.0.0.1:${server.port}/object';
    service = FileService(repository);
  });
  tearDown(() async {
    service.dispose();
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  test(
    'binary PUT has signed headers, progress, no JWT, then confirms',
    () async {
      server.listen((request) async {
        repository.calls.add('put');
        expect(request.method, 'PUT');
        expect(request.headers.value('Authorization'), isNull);
        expect(request.headers.value('Content-Type'), 'image/jpeg');
        expect(request.headers.contentLength, 4);
        expect(await request.fold<List<int>>([], (a, b) => [...a, ...b]), [
          1,
          2,
          3,
          4,
        ]);
        request.response.statusCode = 200;
        await request.response.close();
      });
      final states = <FileUploadState>[];
      var progress = false;
      final result = await service.uploadFile(
        file: file,
        category: 'image',
        onState: states.add,
        onSendProgress: (sent, total) {
          progress = sent == total;
        },
      );
      expect(result.id, 1);
      expect(repository.calls, ['sign', 'put', 'complete']);
      expect(states.first.phase, UploadPhase.preparing);
      expect(states.last.phase, UploadPhase.success);
      expect(states.last.progress, 1);
      expect(progress, isTrue);
    },
  );

  test('cancel after binary upload prevents completion', () async {
    final token = CancelToken();
    server.listen((request) async {
      await request.drain<void>();
      token.cancel();
      await request.response.close();
    });
    await expectLater(
      service.uploadFile(file: file, category: 'image', cancelToken: token),
      throwsA(isA<FileTransferException>()),
    );
    expect(repository.confirms, 0);
  });

  test('cancel before upload does not sign or confirm', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      service.uploadFile(file: file, category: 'image', cancelToken: token),
      throwsA(isA<FileTransferException>()),
    );
    expect(repository.calls, isEmpty);
  });

  test('failed PUT does not confirm or leak signed URL in error', () async {
    repository.url += '?Signature=private';
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 403;
      await request.response.close();
    });
    await expectLater(
      service.uploadFile(file: file, category: 'image'),
      throwsA(
        isA<FileTransferException>().having(
          (e) => e.message.contains('private'),
          'redacted',
          false,
        ),
      ),
    );
    expect(repository.confirms, 0);
  });

  test('download refreshes expired signature once and writes bytes', () async {
    var requests = 0;
    server.listen((request) async {
      expect(request.headers.value('Authorization'), isNull);
      requests++;
      request.response.statusCode = requests == 1 ? 403 : 200;
      request.response.add([5, 6, 7]);
      await request.response.close();
    });
    final result = await service.downloadFile(
      fileId: 1,
      savePath: '${temp.path}/download.jpg',
    );
    expect(await result.readAsBytes(), [5, 6, 7]);
    expect(repository.downloadSigns, 2);
  });

  test(
    'repeated download 403 stops after two requests and removes partial file',
    () async {
      server.listen((request) async {
        request.response.statusCode = 403;
        await request.response.close();
      });
      final path = '${temp.path}/download.jpg';
      await expectLater(
        service.downloadFile(fileId: 1, savePath: path),
        throwsA(isA<FileTransferException>()),
      );
      expect(repository.downloadSigns, 2);
      expect(await File(path).exists(), isFalse);
    },
  );

  test('cancelled download does not request signature', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      service.downloadFile(
        fileId: 1,
        savePath: '${temp.path}/cancelled.jpg',
        cancelToken: token,
      ),
      throwsA(isA<FileTransferException>()),
    );
    expect(repository.downloadSigns, 0);
  });
}
