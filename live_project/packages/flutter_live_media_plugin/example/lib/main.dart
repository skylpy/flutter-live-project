import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_live_core/flutter_live_core.dart';
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
        body: const _PlayerDemo(),
      ),
    );
  }
}

/// 真机验收页面：打开后会自动播放公开 HLS 测试流。
///
/// 验证重连时可以临时关闭设备网络，观察状态变成“重连中”；恢复网络后，
/// ExoPlayer 会按 1、2、4 秒退避重新请求清单，成功后状态回到“播放中”。
class _PlayerDemo extends StatefulWidget {
  const _PlayerDemo();

  @override
  State<_PlayerDemo> createState() => _PlayerDemoState();
}

class _PlayerDemoState extends State<_PlayerDemo> {
  static const _demoHlsUrl =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  late final FlutterLiveMediaEngine _engine;
  StreamSubscription<LiveEngineEvent>? _eventSubscription;
  String _status = '正在初始化';
  int? _retryCount;

  @override
  void initState() {
    super.initState();
    _engine = FlutterLiveMediaEngine();
    // 事件由 Android Kotlin → Pigeon FlutterApi → Dart Engine 传回；页面只关心
    // 统一的 LiveEngineEvent，不需要依赖 ExoPlayer 的类或回调类型。
    _eventSubscription = _engine.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _status = event.message ?? event.type.name;
        _retryCount = event.type == LiveEngineEventType.reconnecting
            ? _parseRetryCount(event.message)
            : null;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    // 先取消监听再释放引擎，避免原生异步事件在页面销毁后更新 State。
    _eventSubscription?.cancel();
    _engine.stop();
    _engine.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    // 初始化只负责建立原生播放器生命周期，play 才会创建 HLS MediaSource。
    await _engine.initialize();
    await _engine.play(_demoHlsUrl);
  }

  Future<void> _stop() => _engine.stop();

  int? _parseRetryCount(String? message) {
    final match = RegExp(r'第 (\d+) 次').firstMatch(message ?? '');
    return int.tryParse(match?.group(1) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Android 真机 HLS 播放验收'),
          const SizedBox(height: 8),
          const Text(
            '关闭/恢复设备网络即可验证自动重连。正式直播地址由业务接口传入。',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text('状态：$_status${_retryCount == null ? '' : '（第 $_retryCount 次）'}'),
          const SizedBox(height: 12),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: FlutterLiveMediaPlayerView(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('播放 HLS'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
