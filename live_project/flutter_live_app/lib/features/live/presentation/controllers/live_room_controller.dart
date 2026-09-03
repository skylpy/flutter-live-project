import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/live_room.dart';
import 'live_list_controller.dart';

final liveRoomControllerProvider = FutureProvider.autoDispose
    .family<LiveRoom, String>(
      (ref, roomId) =>
          ref.watch(liveRepositoryProvider).getLiveRoomDetail(roomId),
    );
