import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/feed_post.dart';

/// 图片使用手势缩放，视频使用原尺寸比例播放；动态流和发布页共享这一页。
class MediaViewerPage extends StatelessWidget {
  const MediaViewerPage({
    required this.media,
    this.initialIndex = 0,
    super.key,
  });

  final List<FeedMedia> media;
  final int initialIndex;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: media.length > 1
          ? Text('${initialIndex + 1}/${media.length}')
          : null,
    ),
    body: PageView.builder(
      controller: PageController(initialPage: initialIndex),
      itemCount: media.length,
      itemBuilder: (context, index) => _RemoteMediaView(media: media[index]),
    ),
  );
}

class LocalMediaViewerPage extends StatelessWidget {
  const LocalMediaViewerPage({
    required this.file,
    required this.isVideo,
    super.key,
  });

  final XFile file;
  final bool isVideo;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: isVideo
          ? _VideoPlayer(
              fileController: VideoPlayerController.file(File(file.path)),
            )
          : InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.file(File(file.path), fit: BoxFit.contain),
            ),
    ),
  );
}

class _RemoteMediaView extends StatelessWidget {
  const _RemoteMediaView({required this.media});

  final FeedMedia media;

  @override
  Widget build(BuildContext context) => Center(
    child: media.isVideo
        ? _VideoPlayer(
            fileController: VideoPlayerController.networkUrl(
              Uri.parse(media.url),
            ),
          )
        : InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Image.network(
              media.url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
  );
}

class _VideoPlayer extends StatefulWidget {
  const _VideoPlayer({required this.fileController});

  final VideoPlayerController fileController;

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.fileController
        .initialize()
        .then((_) {
          if (mounted) setState(() => _ready = true);
        })
        .catchError((_) {
          if (mounted) setState(() => _ready = false);
        });
  }

  @override
  void dispose() {
    widget.fileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const CircularProgressIndicator(color: Colors.white);
    final controller = widget.fileController;
    return GestureDetector(
      onTap: () => setState(
        () =>
            controller.value.isPlaying ? controller.pause() : controller.play(),
      ),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (!controller.value.isPlaying)
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
          ],
        ),
      ),
    );
  }
}
