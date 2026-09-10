import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/live_engine_provider.dart';
import '../../../../core/network/api_provider.dart';
import '../../../live/data/datasources/live_chat_client.dart';
import '../../../live/data/models/live_chat_message.dart';
import '../../../live/data/models/live_room.dart';
import '../../../live/domain/repositories/live_repository.dart';
import '../../../live/presentation/controllers/live_list_controller.dart';
import '../../../live/presentation/widgets/live_danmaku_list.dart';
import '../../../live/presentation/widgets/live_gift_effect.dart';
import '../../../live/presentation/widgets/live_gift_stats_sheet.dart';
import '../../../wallet/presentation/controllers/wallet_controller.dart';

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
  late final LiveChatClient _chatClient;
  StreamSubscription<LiveEngineEvent>? _engineSubscription;
  StreamSubscription<LiveChatMessage>? _chatSubscription;
  final List<LiveChatMessage> _danmaku = [];

  String _status = '正在准备摄像头…';
  int _onlineCount = 0;
  bool _isLiving = false;
  bool _isStopping = false;
  bool _failureCleanupStarted = false;
  bool _isSwitchingCamera = false;
  int _giftRevenue = 0;
  LiveGiftEvent? _activeGift;
  LiveBeautySettings _beautySettings = const LiveBeautySettings();
  Timer? _beautyUpdateDebounce;

  @override
  void initState() {
    super.initState();
    _onlineCount = widget.room.onlineCount;
    _enterFullscreenLiveMode();
    _engine = ref.read(liveEngineProvider);
    _chatClient = LiveChatClient();
    _engineSubscription = _engine.events.listen(_onEngineEvent);
    unawaited(_connectChat());
    unawaited(_loadGiftStats());

    // Android Activity 在 Manifest 中固定为竖屏，这里再做一次运行时锁定，
    // 等待系统完成方向切换后才启动摄像头，避免真机仍处于横屏时先创建出
    // 横向的预览 Surface。
    unawaited(_lockPortraitAndStart());
  }

  Future<void> _connectChat() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    if (!mounted || token == null || token.isEmpty) return;
    _chatSubscription = _chatClient.messages.listen((message) {
      if (!mounted) return;
      setState(() {
        if (message.onlineCount != null) {
          _onlineCount = message.onlineCount!;
        }
        if (_isPublicLiveMessage(message)) {
          _danmaku.add(message);
          if (_danmaku.length > 120) _danmaku.removeAt(0);
        }
        if (message.type == 'gift' && message.gift != null) {
          _activeGift = message.gift;
          _giftRevenue = message.gift!.anchorIncome;
        }
      });
    });
    try {
      await _chatClient.connect(widget.room.id.toString(), token);
    } catch (_) {
      // 主播仍可继续推流；弹幕连接失败不应影响视频链路。
    }
  }

  Future<void> _loadGiftStats() async {
    try {
      final stats = await ref
          .read(walletRepositoryProvider)
          .getRoomGiftStats(widget.room.id.toString());
      if (mounted) setState(() => _giftRevenue = stats.totalRevenue);
    } catch (_) {
      // 礼物统计失败不能阻断摄像头预览或推流；实时礼物到达时仍会更新收益。
    }
  }

  Future<void> _lockPortraitAndStart() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBroadcast());
    });
  }

  void _enterFullscreenLiveMode() {
    // 让原生视频视图延伸到状态栏和底部手势区域，Flutter 控件再使用
    // MediaQuery.paddingOf(context) 主动避让，避免视频上下出现系统栏黑边。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _beautyUpdateDebounce?.cancel();
    _engineSubscription?.cancel();
    _chatSubscription?.cancel();
    unawaited(_chatClient.dispose());
    // 页面被系统返回手势销毁时兜底停止原生推流。正常点击结束按钮时，
    // _stopBroadcast 已经先完成后端状态同步，这里再次 stopPush 也是幂等的。
    // 用户主动结束时，_finishBroadcastInBackground 已经在后台调用 stopPush。
    // 不要在页面销毁时再发第二次原生 MethodChannel 请求；iOS 上两次停止
    // 会串行等待，导致虽然路由已返回，开播页仍出现一段不可操作的停顿。
    if (!_isStopping) unawaited(_engine.stopPush());
    // Android 在 Manifest 中固定为 portrait；这里不能再传空列表，
    // 否则会把 Activity 恢复成 UNSPECIFIED，系统又可能切回横屏。
    // iOS 没有同样的 Manifest 固定，因此离开主播页后恢复系统默认方向。
    if (defaultTargetPlatform != TargetPlatform.android) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _onEngineEvent(LiveEngineEvent event) {
    if (!mounted) return;
    setState(() {
      _status = event.message ?? '推流状态已更新';
    });
    if (event.type == LiveEngineEventType.pushStarted) {
      unawaited(_markRoomLiving());
    } else if (event.type == LiveEngineEventType.error) {
      // 推流建立后仍可能因为编码器、网络或媒体服务断开而收到错误；不能
      // 只处理“启动阶段”的错误，否则房间会永久停在 living。
      unawaited(_handleMediaFailure(event.message ?? '原生媒体引擎异常'));
    }
  }

  Future<void> _startBroadcast() async {
    try {
      await _engine.initialize();
      // 先写入原生链路，再开始采集。这样第一帧主播预览和 RTMP 编码画面就
      // 使用同一组美颜参数，而不是开播后才突然发生颜色/磨皮跳变。
      await _engine.setBeautySettings(_beautySettings);
      await _engine.startPreview();
      await _engine.startPush(widget.room.pushUrl);
    } catch (error) {
      await _cleanupRoom();
      if (!mounted) return;
      setState(() {
        _status = '推流启动失败：$error';
      });
    }
  }

  Future<void> _markRoomLiving() async {
    if (_isLiving) return;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        // 后端会再向 SRS 确认 stream.active。iOS/Android 刚收到 publish
        // 成功事件时，SRS 的状态 API 可能还差几百毫秒才更新，所以这里做少量
        // 有界重试；既不会无限请求，也不会把“黑屏房间”标记成 living。
        await ref
            .read(liveRepositoryProvider)
            .startLiveRoom(widget.room.id.toString());
        if (!mounted) return;
        setState(() {
          _isLiving = true;
          _status = '直播中';
        });
        ref.invalidate(liveListControllerProvider);
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (mounted) {
      await _stopPushSafely();
      await _cleanupRoom();
      if (!mounted) return;
      setState(() {
        _status = '推流状态确认失败，房间已清理：$lastError';
      });
    }
  }

  Future<void> _handleMediaFailure(String message) async {
    if (_isStopping || _failureCleanupStarted) return;
    _failureCleanupStarted = true;
    if (mounted) {
      setState(() {
        _isLiving = false;
        _isStopping = true;
        _status = '$message，正在清理直播间…';
      });
    }
    await _stopPushSafely();
    await _cleanupRoom();
    if (!mounted) return;
    setState(() {
      _isStopping = false;
      _status = '$message，房间已结束';
    });
  }

  Future<void> _cleanupRoom() async {
    try {
      await ref
          .read(liveRepositoryProvider)
          .stopLiveRoom(widget.room.id.toString())
          .timeout(const Duration(seconds: 5));
      ref.invalidate(liveListControllerProvider);
    } catch (_) {
      // 后端不可达时仍保持页面可关闭；服务端定时清理会处理孤儿 preparing 房间。
    }
  }

  Future<void> _stopPushSafely() async {
    try {
      await _engine.stopPush().timeout(const Duration(seconds: 5));
    } catch (_) {
      // 原生引擎已断开时 stopPush 可能无法及时返回，不能阻塞房间状态清理。
    }
  }

  /// 结束按钮的页面反馈必须立即完成，尤其是 iOS 的原生推流停止需要等待
  /// AVFoundation 回调时。房间收尾在后台并行执行：停止推流和标记 ended 互不
  /// 依赖，因此不应让用户在主播页等待两次网络/原生超时。
  void _stopBroadcast() {
    if (_isStopping) return;
    setState(() {
      _isStopping = true;
      _status = '正在结束直播…';
    });

    final repository = ref.read(liveRepositoryProvider);
    final listController = ref.read(liveListControllerProvider.notifier);
    unawaited(_finishBroadcastInBackground(repository, listController));
    Navigator.of(context).pop(true);
  }

  Future<void> _finishBroadcastInBackground(
    LiveRepository repository,
    LiveListController listController,
  ) async {
    try {
      await Future.wait<void>([
        _stopPushSafely(),
        repository
            .stopLiveRoom(widget.room.id.toString())
            .timeout(const Duration(seconds: 5)),
      ]);
      // CreateLivePage 会在路由返回时立刻刷新一次；这里在服务端真正进入
      // ended 后再刷新一次，避免首页短暂保留“直播中”的旧卡片。
      await listController.refreshRooms();
    } catch (_) {
      // 页面已即时退出。若本次网络请求异常，服务端的孤儿房间协调任务仍会
      // 清理推流已结束的房间；不再把用户拉回主播页等待错误提示。
    }
  }

  void _handleBackNavigation() => _stopBroadcast();

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _isStopping) return;
    setState(() => _isSwitchingCamera = true);
    try {
      await _engine.switchCamera();
      if (!mounted) return;
      setState(() => _status = '摄像头已切换');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '切换摄像头失败：$error');
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  void _scheduleBeautyUpdate(LiveBeautySettings settings) {
    final normalized = settings.normalized;
    setState(() => _beautySettings = normalized);
    // Slider 每一帧都会产生值。小幅防抖避免高频 Platform Channel 调用抢占
    // Camera/GL 线程，同时保持拖动时肉眼可见的实时反馈。
    _beautyUpdateDebounce?.cancel();
    _beautyUpdateDebounce = Timer(const Duration(milliseconds: 48), () async {
      try {
        await _engine.setBeautySettings(normalized);
      } catch (error) {
        if (!mounted) return;
        setState(() => _status = '美颜参数更新失败：$error');
      }
    });
  }

  Future<void> _showBeautyPanel() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final primary = Theme.of(context).colorScheme.primary;
            final settings = _beautySettings;
            void update(LiveBeautySettings next) {
              _scheduleBeautyUpdate(next);
              setSheetState(() {});
            }

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                decoration: const BoxDecoration(
                  color: Color(0xF21A1720),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '实时美颜',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => update(LiveBeautySettings.disabled),
                          child: const Text('原图'),
                        ),
                      ],
                    ),
                    const Text(
                      '效果会同步到主播预览和观众画面',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _BeautySlider(
                      label: '磨皮',
                      value: settings.smoothing,
                      color: primary,
                      onChanged: (value) =>
                          update(settings.copyWith(smoothing: value)),
                    ),
                    _BeautySlider(
                      label: '美白',
                      value: settings.whitening,
                      color: primary,
                      onChanged: (value) =>
                          update(settings.copyWith(whitening: value)),
                    ),
                    _BeautySlider(
                      label: '红润',
                      value: settings.rosiness,
                      color: primary,
                      onChanged: (value) =>
                          update(settings.copyWith(rosiness: value)),
                    ),
                    _BeautySlider(
                      label: '瘦脸',
                      value: settings.faceSlimming,
                      color: primary,
                      onChanged: (value) =>
                          update(settings.copyWith(faceSlimming: value)),
                    ),
                    _BeautySlider(
                      label: '滤镜强度',
                      value: settings.filterStrength,
                      color: primary,
                      onChanged: (value) =>
                          update(settings.copyWith(filterStrength: value)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 摄像头预览和推流画布铺满屏幕，编码仍固定为 720x1280 竖屏；
            // 原生视图由 Android/iOS 自己按容器裁切，避免页面出现横向留白。
            const Positioned.fill(child: FlutterLiveMediaPublisherView()),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              right: 16,
              child: _BroadcastHeader(
                room: widget.room,
                status: _status,
                onlineCount: _onlineCount,
                giftRevenue: _giftRevenue,
                onShowGiftStats: () => showLiveGiftStatsSheet(
                  context,
                  roomId: widget.room.id.toString(),
                ),
                onBeauty: _isStopping ? null : _showBeautyPanel,
                onSwitchCamera: _isStopping ? null : _switchCamera,
                onClose: _isStopping ? null : _stopBroadcast,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 28,
              child: IgnorePointer(child: LiveDanmakuList(messages: _danmaku)),
            ),
            // 高价值礼物使用整屏舞台层；该层忽略触摸，主播仍可切换摄像头或结束。
            Positioned.fill(child: LiveGiftEffect(gift: _activeGift)),
          ],
        ),
      ),
    );
  }
}

bool _isPublicLiveMessage(LiveChatMessage message) =>
    message.type == 'chat' ||
    message.type == 'presence' ||
    message.type == 'system' ||
    message.type == 'gift';

class _BroadcastHeader extends StatelessWidget {
  const _BroadcastHeader({
    required this.room,
    required this.status,
    required this.onlineCount,
    required this.giftRevenue,
    required this.onShowGiftStats,
    required this.onBeauty,
    required this.onSwitchCamera,
    required this.onClose,
  });

  final LiveRoom room;
  final String status;
  final int onlineCount;
  final int giftRevenue;
  final VoidCallback onShowGiftStats;
  final VoidCallback? onBeauty;
  final VoidCallback? onSwitchCamera;
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
                '$status · $onlineCount 人在线 · 收益 $giftRevenue',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onShowGiftStats,
          color: Colors.white,
          icon: const Icon(Icons.emoji_events_outlined),
          tooltip: '礼物榜单',
        ),
        IconButton(
          onPressed: onBeauty,
          color: Colors.white,
          icon: const Icon(Icons.auto_awesome_outlined),
          tooltip: '实时美颜',
        ),
        IconButton(
          onPressed: onSwitchCamera,
          color: Colors.white,
          icon: const Icon(Icons.flip_camera_ios_outlined),
          tooltip: '切换前后摄像头',
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

class _BeautySlider extends StatelessWidget {
  const _BeautySlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: Colors.white24,
                overlayColor: color.withValues(alpha: 0.16),
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(value * 100).round()}',
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
