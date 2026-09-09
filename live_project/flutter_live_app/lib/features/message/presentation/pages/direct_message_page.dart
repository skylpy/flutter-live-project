import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_provider.dart';
import '../../../../core/realtime/realtime_notification_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../discover/data/models/feed_post.dart';
import '../../../discover/presentation/pages/media_viewer_page.dart';
import '../../../files/data/models/app_file.dart';
import '../../../files/presentation/controllers/file_controller.dart';
import '../../data/models/direct_message.dart';
import '../controllers/message_controller.dart';

/// 一对一即时通讯页。
///
/// 历史消息从 REST 恢复，收到用户级 WebSocket 推送时直接追加；图片和视频
/// 仍走统一的 OSS 上传/签名下载链路，因此不会把私有附件 URL 写到本地缓存。
class DirectMessagePage extends ConsumerStatefulWidget {
  const DirectMessagePage({
    required this.otherUserId,
    required this.otherUserName,
    super.key,
  });

  final int otherUserId;
  final String otherUserName;

  @override
  ConsumerState<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends ConsumerState<DirectMessagePage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final List<XFile> _selectedFiles = [];
  final Map<String, AppFile> _uploadedByPath = {};
  late final StreamSubscription<RealtimeNotificationEvent>
  _realtimeSubscription;

  List<DirectMessage> _messages = const [];
  Object? _loadError;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = ref
        .read(realtimeNotificationClientProvider)
        .events
        .listen(_onRealtimeEvent);
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _realtimeSubscription.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final history = await ref
          .read(messageRepositoryProvider)
          .getConversation(widget.otherUserId);
      if (!mounted) return;
      _mergeMessages(history);
      ref.invalidate(messageControllerProvider);
      _scrollToLatest();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onRealtimeEvent(RealtimeNotificationEvent event) {
    if (event.type != 'notification' || event.event != 'message') return;
    final rawMessage = event.message;
    if (rawMessage == null) return;
    final message = DirectMessage.fromJson(rawMessage);
    if (message.senderId != widget.otherUserId &&
        message.recipientId != widget.otherUserId) {
      return;
    }
    _mergeMessages([message]);
    _scrollToLatest();
    ref.invalidate(messageControllerProvider);
  }

  void _mergeMessages(Iterable<DirectMessage> incoming) {
    final byId = <int, DirectMessage>{
      for (final message in _messages) message.id: message,
      for (final message in incoming) message.id: message,
    };
    final next = byId.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    if (mounted) setState(() => _messages = next);
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  bool get _hasVideo => _selectedFiles.any((file) => _typeFor(file) == 'video');

  String _typeFor(XFile file) {
    if (file.mimeType?.startsWith('video/') == true) return 'video';
    final extension = file.name.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v', 'avi'}.contains(extension)
        ? 'video'
        : 'image';
  }

  Future<void> _showMediaPicker() async {
    if (_sending) return;
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
                unawaited(_pickImages());
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('从相册选择视频'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_pickVideo());
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
      _show('视频消息不能与图片混用');
      return;
    }
    final files = await _picker.pickMultiImage(imageQuality: 92);
    if (!mounted || files.isEmpty) return;
    if (_selectedFiles.length + files.length > 9) {
      _show('一次最多发送 9 张图片');
      return;
    }
    setState(() => _selectedFiles.addAll(files));
  }

  Future<void> _pickVideo() async {
    if (_selectedFiles.isNotEmpty) {
      _show('视频消息只能发送一个视频，不能与图片混用');
      return;
    }
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() => _selectedFiles.add(file));
  }

  void _removeMedia(XFile file) {
    setState(() {
      _selectedFiles.remove(file);
      _uploadedByPath.remove(file.path);
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final body = _inputController.text.trim();
    if (body.isEmpty && _selectedFiles.isEmpty) return;
    setState(() => _sending = true);
    try {
      for (final file in List<XFile>.from(_selectedFiles)) {
        if (_uploadedByPath.containsKey(file.path)) continue;
        final uploaded = await ref
            .read(fileUploadControllerProvider.notifier)
            .uploadXFile(file, _typeFor(file));
        if (uploaded == null) {
          throw _ChatException(
            ref.read(fileUploadControllerProvider).errorMessage ?? '媒体上传失败',
          );
        }
        if (!mounted) return;
        setState(() => _uploadedByPath[file.path] = uploaded);
      }
      final message = await ref
          .read(messageRepositoryProvider)
          .sendMessage(
            recipientId: widget.otherUserId,
            body: body,
            fileIds: _selectedFiles
                .map((file) => _uploadedByPath[file.path]!.id)
                .toList(growable: false),
          );
      if (!mounted) return;
      setState(() {
        _inputController.clear();
        _selectedFiles.clear();
        _uploadedByPath.clear();
      });
      _mergeMessages([message]);
      _scrollToLatest();
      ref.invalidate(messageControllerProvider);
    } on _ChatException catch (error) {
      _show(error.message);
    } on ApiException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('发送失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final upload = ref.watch(fileUploadControllerProvider);
    final busy = _sending || upload.busy;
    final tokens = AppTheme.tokens(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            InkWell(
              onTap: () => context.push('/feed/users/${widget.otherUserId}'),
              borderRadius: BorderRadius.circular(22),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: tokens.secondary.withValues(alpha: 0.23),
                child: Text(
                  widget.otherUserName.isEmpty ? '?' : widget.otherUserName[0],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUserName.isEmpty ? '私信' : widget.otherUserName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildTimeline(tokens)),
          if (_selectedFiles.isNotEmpty)
            _PendingMediaBar(
              files: _selectedFiles,
              typeFor: _typeFor,
              onRemove: busy ? null : _removeMedia,
            ),
          if (upload.busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: LinearProgressIndicator(value: upload.progress),
            ),
          _Composer(
            controller: _inputController,
            busy: busy,
            onPickMedia: _showMediaPicker,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(LiveThemeExtension tokens) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _messages.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('加载消息失败，重试'),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('开始和 TA 聊聊吧'));
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 13),
      itemBuilder: (context, index) => _ChatBubble(
        message: _messages[index],
        tokens: tokens,
        onOpenUserProfile: (userId) => context.push('/feed/users/$userId'),
        onOpenMedia: (media) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaViewerPage(
              media: media
                  .map(
                    (item) => FeedMedia(
                      fileId: item.fileId,
                      mediaType: item.mediaType,
                      url: item.url,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.tokens,
    required this.onOpenUserProfile,
    required this.onOpenMedia,
  });

  final DirectMessage message;
  final LiveThemeExtension tokens;
  final ValueChanged<int> onOpenUserProfile;
  final ValueChanged<List<DirectMessageMedia>> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final maxWidth = MediaQuery.sizeOf(context).width * .72;
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          InkWell(
            onTap: () => onOpenUserProfile(message.senderId),
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: tokens.secondary.withValues(alpha: .23),
              child: const Icon(Icons.person, size: 18),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: mine ? tokens.primary : tokens.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 16),
                    ),
                    border: mine
                        ? null
                        : Border.all(
                            color: tokens.divider.withValues(alpha: .55),
                          ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.media.isNotEmpty)
                          _MessageMediaGrid(
                            media: message.media,
                            onTap: () => onOpenMedia(message.media),
                          ),
                        if (message.body.isNotEmpty) ...[
                          if (message.media.isNotEmpty)
                            const SizedBox(height: 8),
                          Text(
                            message.body,
                            style: TextStyle(
                              color: mine ? Colors.white : tokens.textPrimary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message.timeLabel,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 7),
          InkWell(
            onTap: () => onOpenUserProfile(message.senderId),
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: tokens.primary.withValues(alpha: .22),
              child: const Icon(Icons.person, size: 18),
            ),
          ),
        ],
      ],
    );
  }
}

class _MessageMediaGrid extends StatelessWidget {
  const _MessageMediaGrid({required this.media, required this.onTap});

  final List<DirectMessageMedia> media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = media.length;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final item in media)
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: count == 1 ? 190 : 106,
                height: count == 1 ? 190 : 106,
                child: item.isVideo
                    ? ColoredBox(
                        color: Colors.black87,
                        child: Stack(
                          alignment: Alignment.center,
                          children: const [
                            Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 42,
                            ),
                            Positioned(
                              bottom: 9,
                              left: 9,
                              child: Text(
                                '视频',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Image.network(
                        item.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PendingMediaBar extends StatelessWidget {
  const _PendingMediaBar({
    required this.files,
    required this.typeFor,
    required this.onRemove,
  });

  final List<XFile> files;
  final String Function(XFile) typeFor;
  final ValueChanged<XFile>? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    height: 82,
    padding: const EdgeInsets.fromLTRB(14, 7, 14, 5),
    decoration: const BoxDecoration(color: Color(0xFFF7F7F9)),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final file = files[index];
        final video = typeFor(file) == 'video';
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 68,
                height: 68,
                child: video
                    ? const ColoredBox(
                        color: Colors.black87,
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                        ),
                      )
                    : Image.file(File(file.path), fit: BoxFit.cover),
              ),
            ),
            Positioned(
              top: -5,
              right: -5,
              child: IconButton.filled(
                onPressed: onRemove == null ? null : () => onRemove!(file),
                icon: const Icon(Icons.close, size: 14),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onPickMedia,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onPickMedia;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: .06)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: '相册',
            onPressed: busy ? null : onPickMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !busy,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '发消息…',
                counterText: '',
                filled: true,
                fillColor: Colors.black.withValues(alpha: .055),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: '发送',
            onPressed: busy ? null : onSend,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    ),
  );
}

class _ChatException implements Exception {
  const _ChatException(this.message);
  final String message;
}
