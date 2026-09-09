import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/app_file.dart';
import '../../data/services/file_service.dart';
import '../controllers/file_controller.dart';

/// 最小文件管理入口：签名、直传、查看、下载、删除均使用真实 Repository。
class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});
  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final _files = <AppFile>[];
  String _category = 'image';
  String? _error;
  bool _loading = false;
  bool _more = true;
  CancelToken? _downloadToken;
  double _downloadProgress = 0;
  String? _downloadName;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _downloadToken?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await ref
          .read(fileRepositoryProvider)
          .listFiles(
            beforeId: more && _files.isNotEmpty ? _files.last.id : null,
          );
      if (!mounted) return;
      setState(() {
        if (!more) _files.clear();
        _files.addAll(files);
        _more = files.length == 30;
      });
    } catch (error) {
      if (mounted) setState(() => _error = fileErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.pickFile();
      if (!mounted || picked == null) return;
      final file = await ref
          .read(fileUploadControllerProvider.notifier)
          .upload(picked, _category);
      if (mounted && file != null) await _load();
    } catch (error) {
      if (mounted) _snack(fileErrorMessage(error));
    }
  }

  Future<void> _view(AppFile file) async {
    try {
      final fresh = await ref.read(fileRepositoryProvider).getFile(file.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(fresh.originalFilename),
          content: fresh.contentType.startsWith('image/') && fresh.url != null
              ? Image.network(
                  fresh.url!,
                  errorBuilder: (_, _, _) => const Text('图片加载失败，请关闭后重新查看'),
                )
              : Text('${fresh.contentType}\n${fresh.fileSize} 字节\n可下载到本机查看'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _snack(fileErrorMessage(error));
    }
  }

  Future<void> _download(AppFile file) async {
    final token = CancelToken();
    setState(() {
      _downloadToken = token;
      _downloadName = file.originalFilename;
      _downloadProgress = 0;
    });
    try {
      final directory = await getApplicationDocumentsDirectory();
      // 使用独立目录保留原始名称，避免覆盖用户已下载的文件。
      final target = await Directory(
        '${directory.path}/downloads/${file.id}-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final saved = await ref
          .read(fileServiceProvider)
          .downloadFile(
            fileId: file.id,
            savePath: '${target.path}/${file.originalFilename}',
            cancelToken: token,
            onProgress: (received, total) {
              if (mounted) {
                setState(
                  () => _downloadProgress = total > 0
                      ? (received / total).clamp(0, 1)
                      : 0,
                );
              }
            },
          );
      if (mounted) _snack('已下载到 ${saved.path}');
    } catch (error) {
      if (mounted) _snack(fileErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _downloadToken = null;
          _downloadName = null;
        });
      }
    }
  }

  Future<void> _delete(AppFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件？'),
        content: Text(file.originalFilename),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    try {
      await ref.read(fileServiceProvider).deleteFile(file.id);
      if (mounted) {
        setState(() => _files.removeWhere((item) => item.id == file.id));
      }
    } catch (error) {
      if (mounted) _snack(fileErrorMessage(error));
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final upload = ref.watch(fileUploadControllerProvider);
    ref.watch(fileServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的文件')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '文件分类'),
              items:
                  const [
                        'image',
                        'avatar',
                        'pdf',
                        'document',
                        'audio',
                        'video',
                        'source',
                        'result',
                      ]
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged: upload.busy
                  ? null
                  : (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: upload.busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('选择文件并上传'),
            ),
            if (upload.busy) ...[
              LinearProgressIndicator(
                value: upload.phase == UploadPhase.preparing
                    ? null
                    : upload.progress,
              ),
              Text(switch (upload.phase) {
                UploadPhase.preparing => '准备上传…',
                UploadPhase.confirming => '确认上传…',
                _ => '正在上传 ${(upload.progress * 100).round()}%',
              }),
              TextButton(
                onPressed: upload.phase == UploadPhase.confirming
                    ? null
                    : ref
                          .read(fileUploadControllerProvider.notifier)
                          .cancelUpload,
                child: const Text('取消上传'),
              ),
            ],
            if (upload.phase == UploadPhase.success) const Text('上传成功'),
            if (upload.errorMessage != null) Text(upload.errorMessage!),
            if (_downloadName != null) ...[
              Text('下载 $_downloadName：${(_downloadProgress * 100).round()}%'),
              LinearProgressIndicator(value: _downloadProgress),
              TextButton(
                onPressed: () => _downloadToken?.cancel(),
                child: const Text('取消下载'),
              ),
            ],
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
            if (!_loading && _files.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无文件，选择图片或文档开始上传'),
              ),
            for (final file in _files)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.originalFilename),
                      Text('${file.category} · ${file.fileSize} 字节'),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => _view(file),
                            child: const Text('查看'),
                          ),
                          TextButton(
                            onPressed: _downloadToken != null
                                ? null
                                : () => _download(file),
                            child: const Text('下载'),
                          ),
                          TextButton(
                            onPressed: () => _delete(file),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _more && _files.isNotEmpty)
              TextButton(
                onPressed: () => _load(more: true),
                child: const Text('加载更多'),
              ),
          ],
        ),
      ),
    );
  }
}
