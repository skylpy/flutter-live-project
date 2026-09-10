import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../live/data/models/live_room.dart';
import '../../../live/presentation/controllers/live_list_controller.dart';

/// 主播端开播信息页。
///
/// 这一页只负责收集标题、主播名称和申请权限，不直接创建原生摄像头视图。
/// 点击“开始直播”后，先调用后端创建房间，再跳转到 [LiveBroadcastPage]。
///
/// 把表单和推流页拆开有两个好处：
/// 1. 用户还没有确认开播前，不会提前占用摄像头和麦克风；
/// 2. 后续 iOS、Android、HarmonyOS 只需要分别实现 LiveEngine，Flutter
///    主播控制台和后端状态链路都可以复用。
class CreateLivePage extends ConsumerStatefulWidget {
  const CreateLivePage({super.key});

  @override
  ConsumerState<CreateLivePage> createState() => _CreateLivePageState();
}

class _CreateLivePageState extends ConsumerState<CreateLivePage> {
  final _titleController = TextEditingController(text: 'Flutter 直播测试');
  final _anchorController = TextEditingController(text: 'Kevin');

  bool _isStarting = false;
  String _status = '填写信息后开始直播';

  @override
  void dispose() {
    _titleController.dispose();
    _anchorController.dispose();
    super.dispose();
  }

  Future<void> _startLive() async {
    if (_isStarting) return;
    final title = _titleController.text.trim();
    final anchorName = _anchorController.text.trim();
    if (title.isEmpty || anchorName.isEmpty) {
      setState(() => _status = '标题和主播名称不能为空');
      return;
    }

    setState(() {
      _isStarting = true;
      _status = '正在申请摄像头和麦克风权限…';
    });

    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (!mounted) return;
    if (permissions.values.any((status) => !status.isGranted)) {
      setState(() {
        _isStarting = false;
        _status = '需要摄像头和麦克风权限才能开播';
      });
      return;
    }

    LiveRoom? createdRoom;
    try {
      setState(() => _status = '正在创建直播间…');
      createdRoom = await ref
          .read(liveRepositoryProvider)
          .createLiveRoom(title: title, anchorName: anchorName, category: '综合');
      if (!mounted) return;
      if (createdRoom.pushUrl.isEmpty) {
        throw StateError('服务端没有返回推流地址');
      }

      // 一旦房间创建成功，开播表单不再需要维持“正在准备”的禁用状态。
      // 主播页位于根路由栈上，用户结束直播返回本页时就能立刻再次开播或
      // 切换 Tab，不必等待主播页的原生媒体资源释放完毕。
      setState(() {
        _isStarting = false;
        _status = '主播控制台已打开';
      });

      // 使用根 Navigator 打开主播控制台，因此进入下一页后隐藏底部五个 Tab。
      // room 作为路由 extra 传递，避免第二页重复请求并保证使用本次创建的 pushUrl。
      await context.push(
        '/live-broadcast/${createdRoom.id}',
        extra: createdRoom,
      );
      if (!mounted) return;
      ref.invalidate(liveListControllerProvider);
      setState(() {
        _status = '直播已结束，可以再次开播';
      });
    } catch (error) {
      // 创建房间后如果权限、路由或推流页初始化失败，不能遗留 preparing
      // 房间。停止接口本身幂等，清理失败只记录在页面状态，不覆盖原始错误。
      if (createdRoom != null) {
        try {
          await ref
              .read(liveRepositoryProvider)
              .stopLiveRoom(createdRoom.id.toString());
          ref.invalidate(liveListControllerProvider);
        } catch (_) {
          // 网络中断时由后端定时清理兜底；这里不再向用户隐藏原始失败原因。
        }
      }
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _status = '开播失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开播')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_outlined, size: 56),
                SizedBox(height: 12),
                Text('准备好后进入竖屏主播控制台'),
                SizedBox(height: 4),
                Text('摄像头预览会在下一页启动', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _titleController,
            enabled: !_isStarting,
            decoration: const InputDecoration(
              labelText: '直播标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _anchorController,
            enabled: !_isStarting,
            decoration: const InputDecoration(
              labelText: '主播名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(_status),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isStarting ? null : _startLive,
            icon: const Icon(Icons.videocam),
            label: Text(_isStarting ? '正在准备…' : '开始直播'),
          ),
        ],
      ),
    );
  }
}
