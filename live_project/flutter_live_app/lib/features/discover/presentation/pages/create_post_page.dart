import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../files/data/models/app_file.dart';
import '../../../files/presentation/controllers/file_controller.dart';
import '../controllers/feed_controller.dart';
import 'media_viewer_page.dart';

/// 动态发布只从系统相册挑选媒体：先展示本地预览，再安全直传 OSS 并创建动态。
class CreatePostPage extends ConsumerStatefulWidget {
  const CreatePostPage({super.key});

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _bodyController = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _selectedFiles = [];
  final Map<String, AppFile> _uploadedByPath = {};
  bool _submitting = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _hasVideo => _selectedFiles.any((file) => _typeFor(file) == 'video');

  Future<void> _showGalleryPicker() async {
    if (_submitting) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择图片'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('从相册选择视频'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickVideo();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    if (_hasVideo) {
      _show('视频动态不能与图片混用');
      return;
    }
    final picked = await _picker.pickMultiImage(imageQuality: 92);
    if (picked.isEmpty || !mounted) return;
    if (_selectedFiles.length + picked.length > 9) {
      _show('一条动态最多选择 9 张图片');
      return;
    }
    setState(() => _selectedFiles.addAll(picked));
  }

  Future<void> _pickVideo() async {
    if (_selectedFiles.isNotEmpty) {
      _show('视频动态只能选择一个视频，不能与图片混用');
      return;
    }
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _selectedFiles.add(picked));
  }

  String _typeFor(XFile file) {
    if (file.mimeType?.startsWith('video/') == true) return 'video';
    final extension = file.name.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v', 'avi'}.contains(extension)
        ? 'video'
        : 'image';
  }

  void _remove(XFile file) {
    setState(() {
      _selectedFiles.remove(file);
      _uploadedByPath.remove(file.path);
    });
  }

  Future<void> _publish() async {
    if (_submitting) return;
    if (_bodyController.text.trim().isEmpty && _selectedFiles.isEmpty) {
      _show('请写点内容或选择媒体');
      return;
    }
    setState(() => _submitting = true);
    try {
      for (final file in List<XFile>.from(_selectedFiles)) {
        if (_uploadedByPath.containsKey(file.path)) continue;
        final uploaded = await ref
            .read(fileUploadControllerProvider.notifier)
            .uploadXFile(file, _typeFor(file));
        if (uploaded == null) {
          final failure = ref.read(fileUploadControllerProvider).errorMessage;
          throw _PublishException(failure ?? '媒体上传失败');
        }
        if (!mounted) return;
        setState(() => _uploadedByPath[file.path] = uploaded);
      }
      await ref
          .read(feedRepositoryProvider)
          .createPost(
            body: _bodyController.text.trim(),
            fileIds: _selectedFiles
                .map((file) => _uploadedByPath[file.path]!.id)
                .toList(growable: false),
          );
      await ref.read(feedControllerProvider.notifier).refresh();
      if (!mounted) return;
      context.go('/discover');
    } on _PublishException catch (error) {
      _show(error.message);
    } on ApiException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('发布失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    final upload = ref.watch(fileUploadControllerProvider);
    final busy = _submitting || upload.busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布动态'),
        actions: [
          TextButton(
            onPressed: busy ? null : _publish,
            child: Text(_submitting ? '发布中' : '发布'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _bodyController,
              minLines: 6,
              maxLines: 10,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '分享此刻的新鲜事…',
                border: InputBorder.none,
              ),
            ),
            if (_selectedFiles.isNotEmpty) ...[
              _SelectedMediaGrid(
                files: _selectedFiles,
                typeFor: _typeFor,
                uploadedPaths: _uploadedByPath.keys.toSet(),
                disabled: busy,
                onRemove: _remove,
              ),
              const SizedBox(height: 16),
            ],
            OutlinedButton.icon(
              onPressed: busy ? null : _showGalleryPicker,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_selectedFiles.isEmpty ? '从相册选择图片或视频' : '继续选择'),
            ),
            const SizedBox(height: 12),
            Text(
              '最多 9 张图片，或 1 个视频。点击缩略图可预览；媒体将安全直传至 OSS。',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            if (upload.busy) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(value: upload.progress),
              const SizedBox(height: 8),
              Text('正在上传媒体 ${(upload.progress * 100).round()}%'),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedMediaGrid extends StatelessWidget {
  const _SelectedMediaGrid({
    required this.files,
    required this.typeFor,
    required this.uploadedPaths,
    required this.disabled,
    required this.onRemove,
  });

  final List<XFile> files;
  final String Function(XFile file) typeFor;
  final Set<String> uploadedPaths;
  final bool disabled;
  final ValueChanged<XFile> onRemove;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: files.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (context, index) {
      final file = files[index];
      final isVideo = typeFor(file) == 'video';
      return Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LocalMediaViewerPage(file: file, isVideo: isVideo),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isVideo
                  ? _LocalVideoThumbnail(file: file)
                  : Image.file(File(file.path), fit: BoxFit.cover),
            ),
          ),
          if (isVideo)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 36,
              ),
            ),
          if (uploadedPaths.contains(file.path))
            const Positioned(
              left: 6,
              bottom: 6,
              child: Icon(Icons.cloud_done, color: Colors.white, size: 18),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton.filled(
              onPressed: disabled ? null : () => onRemove(file),
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      );
    },
  );
}

class _LocalVideoThumbnail extends StatefulWidget {
  const _LocalVideoThumbnail({required this.file});
  final XFile file;

  @override
  State<_LocalVideoThumbnail> createState() => _LocalVideoThumbnailState();
}

class _LocalVideoThumbnailState extends State<_LocalVideoThumbnail> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.file.path))
      ..initialize()
          .then((_) {
            if (mounted) setState(() => _ready = true);
          })
          .catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black26,
    child: _ready
        ? FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          )
        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _PublishException implements Exception {
  const _PublishException(this.message);
  final String message;
}
