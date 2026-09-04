import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/live_room.dart';
import 'live_list_controller.dart';

/// 按 roomId 加载直播间详情；autoDispose 保证离开页面后释放临时状态。
final liveRoomControllerProvider = FutureProvider.autoDispose
    .family<LiveRoom, String>(
      (ref, roomId) =>
          ref.watch(liveRepositoryProvider).getLiveRoomDetail(roomId),
    );
