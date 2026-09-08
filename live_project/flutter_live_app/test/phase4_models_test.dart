import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_live_app/core/realtime/realtime_notification_client.dart';
import 'package:flutter_live_app/features/notification/data/models/notification_item.dart';
import 'package:flutter_live_app/features/search/data/models/search_result.dart';

void main() {
  test('SearchResult parses grouped phase4 results', () {
    final result = SearchResult.fromJson({
      'users': [
        {'id': 1, 'username': 'kevin', 'displayName': 'Kevin'},
      ],
      'rooms': [
        {
          'id': 2,
          'title': '测试直播',
          'anchorName': 'Kevin',
          'onlineCount': 12,
          'status': 'living',
          'category': '技术',
        },
      ],
      'posts': [
        {'id': 3, 'author': 'Kevin', 'body': '测试动态', 'timeLabel': '刚刚'},
      ],
    });

    expect(result.users.single.displayName, 'Kevin');
    expect(result.rooms.single.onlineCount, 12);
    expect(result.posts.single.timeLabel, '刚刚');
  });

  test('NotificationItem accepts the backend camelCase contract', () {
    final item = NotificationItem.fromJson({
      'id': 'message:1',
      'type': '互动消息',
      'title': 'Kevin',
      'body': '你好',
      'timeLabel': '刚刚',
      'unread': true,
    });

    expect(item.id, 'message:1');
    expect(item.unread, isTrue);
  });

  test('RealtimeNotificationEvent parses notification payloads', () {
    final event = RealtimeNotificationEvent.fromJson({
      'type': 'notification',
      'event': 'room_liked',
      'notification': {
        'id': 'room-like:1:2:3',
        'type': '直播互动',
        'title': '观众',
        'body': '赞了你的直播间',
        'timeLabel': '刚刚',
        'unread': true,
      },
    });

    expect(event.type, 'notification');
    expect(event.event, 'room_liked');
    expect(event.notification?['unread'], isTrue);
  });
}
