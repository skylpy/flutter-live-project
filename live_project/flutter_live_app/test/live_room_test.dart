import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_live_app/features/live/data/models/live_room.dart';

void main() {
  test('LiveRoom round trips API JSON with safe defaults', () {
    const room = LiveRoom(
      id: 7,
      title: '测试直播',
      anchorName: '主播',
      anchorAvatar: '',
      onlineCount: 42,
      coverUrl: '',
      status: 'living',
      playUrl: '',
      category: '技术',
    );

    final restored = LiveRoom.fromJson(room.toJson());

    expect(restored.id, 7);
    expect(restored.anchorName, '主播');
    expect(restored.onlineCount, 42);
    expect(restored.status, 'living');
  });
}
