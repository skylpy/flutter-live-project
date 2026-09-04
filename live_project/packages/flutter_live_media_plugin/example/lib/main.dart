import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';

void main() {
  runApp(const PluginExampleApp());
}

class PluginExampleApp extends StatelessWidget {
  const PluginExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Live media plugin example')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Dart ↔ Pigeon ↔ 原生播放器通信占位'),
              const SizedBox(height: 16),
              Expanded(child: _NativePlayerView()),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativePlayerView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const FlutterLiveMediaPlayerView();
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const FlutterLiveMediaPlayerView();
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const FlutterLiveMediaPlayerView();
    }
    return const ColoredBox(
      color: Colors.black,
      child: Center(child: Text('当前示例仅支持 iOS / macOS / Android')),
    );
  }
}
