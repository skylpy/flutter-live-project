import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/live_engine_provider.dart';
import '../../../live/data/models/live_room.dart';
import '../../../live/presentation/controllers/live_list_controller.dart';

/// 竖屏主播推流页。
///
/// 页面链路：
/// 1. 设置当前页面为竖屏；
/// 2. 创建/初始化平台媒体引擎；
/// 3. 显示 Android Camera2 预览，并使用房间的 pushUrl 开始 RTMP 推流；
/// 4. 收到 pushStarted 后通知后端把房间状态改为 living；
/// 5. 点击结束或返回时停止推流、同步 ended，再返回开播信息页。
///
/// Flutter 只依赖 [LiveEngine]，因此 Android 使用 Kotlin、iOS 使用 Swift
/// 时，主播页和后端状态流程无需分别复制一套。
class LiveBroadcastPage extends ConsumerStatefulWidget {
  const LiveBroadcastPage({required this.room, super.key});

  final LiveRoom room;

  @override
  ConsumerState<LiveBroadcastPage> createState() => _LiveBroadcastPageState();
}

class _LiveBroadcastPageState extends ConsumerState<LiveBroadcastPage> {
  late final LiveEngine _engine;
  StreamSubscription<LiveEngineEvent>? _engineSubscription;

  String _status = '正在准备摄像头…';
  bool _isStarting = true;
  bool _isLiving = false;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(liveEngineProvider);
    _engineSubscription = _engine.events.listen(_onEngineEvent);

    // 主播直播通常使用 9:16 画布。只在主播页锁定竖屏，离开后恢复系统默认方向，
    // 避免观众播放页和其他 Tab 被错误限制为竖屏。
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBroadcast());
  }

  @override
  void dispose() {
    _engineSubscription?.cancel();
    // 页面被系统返回手势销毁时兜底停止原生推流。正常点击结束按钮时，
    // _stopBroadcast 已经先完成后端状态同步，这里再次 stopPush 也是幂等的。
    unawaited(_engine.stopPush());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  void _onEngineEvent(LiveEngineEvent event) {
    if (!mounted) return;
    setState(() {
      _status = event.message ?? '推流状态已更新';
      if (event.type == LiveEngineEventType.pushStarted) {
        _isStarting = false;
      }
    });
    if (event.type == LiveEngineEventType.pushStarted) {
      unawaited(_markRoomLiving());
    }
  }

  Future<void> _startBroadcast() async {
    try {
      await _engine.initialize();
      await _engine.startPreview();
      await _engine.startPush(widget.room.pushUrl);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _status = '推流启动失败：$error';
      });
    }
  }

  Future<void> _markRoomLiving() async {
    if (_isLiving) return;
    try {
      await ref
          .read(liveRepositoryProvider)
          .startLiveRoom(widget.room.id.toString());
      if (!mounted) return;
      setState(() {
        _isLiving = true;
        _status = '直播中';
      });
      ref.invalidate(liveListControllerProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '推流已连接，但房间状态同步失败：$error');
    }
  }

  Future<void> _stopBroadcast() async {
    if (_isStopping) return;
    setState(() {
      _isStopping = true;
      _status = '正在结束直播…';
    });

    await _engine.stopPush();
    try {
      await ref
          .read(liveRepositoryProvider)
          .stopLiveRoom(widget.room.id.toString());
      ref.invalidate(liveListControllerProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStopping = false;
        _status = '推流已停止，但房间状态同步失败：$error';
      });
    }
  }

  Future<void> _handleBackNavigation() async {
    await _stopBroadcast();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: const FlutterLiveMediaPublisherView(),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _BroadcastHeader(
                  room: widget.room,
                  status: _status,
                  onClose: _isStopping ? null : _stopBroadcast,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: FilledButton.icon(
                  onPressed: _isStarting || _isStopping ? null : _stopBroadcast,
                  icon: const Icon(Icons.stop),
                  label: Text(_isStopping ? '正在结束…' : '结束直播'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastHeader extends StatelessWidget {
  const _BroadcastHeader({
    required this.room,
    required this.status,
    required this.onClose,
  });

  final LiveRoom room;
  final String status;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white24,
          child: Text(
            room.anchorName.isEmpty ? '?' : room.anchorName[0],
            style: const TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$status · ${room.anchorName}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          color: Colors.white,
          icon: const Icon(Icons.close),
          tooltip: '结束直播',
        ),
      ],
    );
  }
}
