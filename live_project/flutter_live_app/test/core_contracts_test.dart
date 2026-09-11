import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_live_app/core/auth/token_storage.dart';
import 'package:flutter_live_app/core/network/api_exception.dart';
import 'package:flutter_live_app/core/network/api_response.dart';
import 'package:flutter_live_app/core/network/auth_expired_event_bus.dart';
import 'package:flutter_live_app/features/auth/data/models/auth_session.dart';
import 'package:flutter_live_app/features/live/data/models/live_chat_message.dart';
import 'package:flutter_live_app/features/live/data/models/live_room.dart';

void main() {
  test(
    'ApiResponse parses numeric and invalid business codes consistently',
    () {
      final response = ApiResponse<int>.fromJson({
        'code': '0',
        'message': 'success',
        'data': '42',
      }, (value) => int.parse('$value'));
      expect(response.code, 0);
      expect(response.message, 'success');
      expect(response.data, 42);

      final failed = ApiResponse<Object?>.fromJson({
        'code': '40301',
        'message': '没有权限',
        'data': null,
      }, (value) => value);
      expect(failed.code, 40301);
      expect(failed.data, isNull);
      expect(
        const ApiException(message: '失败', statusCode: 403).toString(),
        '失败',
      );
    },
  );

  test('Auth and live models accept aliases and safe defaults for malformed values', () {
    final session = AuthSession.fromJson({
      'access_token': 'token',
      'token_type': 'bearer',
      'user': {'id': '8', 'username': 'u', 'display_name': '用户'},
    });
    expect(session.accessToken, 'token');
    expect(session.user.id, 8);

    final room = LiveRoom.fromJson({
      'id': '7',
      'title': null,
      'anchor_user_id': 0,
      'online_count': '99',
      'status': null,
      'play_url': null,
    });
    expect(room.id, 7);
    expect(room.title, '');
    expect(room.anchorUserId, isNull);
    expect(room.onlineCount, 99);
    expect(room.status, 'living');

    final gift = LiveChatMessage.fromJson({
      'type': 'gift',
      'userName': '观众',
      'onlineCount': '12',
      'gift': {'id': 'bad', 'quantity': '2', 'giftName': '玫瑰'},
    });
    expect(gift.onlineCount, 12);
    expect(gift.gift?.id, 0);
    expect(gift.gift?.quantity, 2);
  });

  test(
    'TokenStorage caches, persists, and clears the authentication token',
    () async {
      SharedPreferences.setMockInitialValues({'access_token': 'from-disk'});
      final storage = TokenStorage();
      expect(await storage.readToken(), 'from-disk');
      await storage.saveToken('new-token');
      expect(await storage.readToken(), 'new-token');
      await storage.clearToken();
      expect(await storage.readToken(), isNull);
    },
  );

  test(
    'AuthExpiredEventBus emits exactly one event for one expiration',
    () async {
      final bus = AuthExpiredEventBus();
      final events = <void>[];
      final subscription = bus.events.listen(events.add);
      addTearDown(subscription.cancel);
      bus.emit();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
    },
  );
}
