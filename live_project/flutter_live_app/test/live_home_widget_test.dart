import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_live_app/core/theme/app_theme.dart';
import 'package:flutter_live_app/features/home/presentation/pages/home_page.dart';
import 'package:flutter_live_app/features/live/data/models/live_interaction.dart';
import 'package:flutter_live_app/features/live/data/models/live_room.dart';
import 'package:flutter_live_app/features/live/domain/repositories/live_repository.dart';
import 'package:flutter_live_app/features/live/presentation/controllers/live_list_controller.dart';
import 'package:flutter_live_app/features/live/presentation/widgets/live_room_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WidgetLiveRepository implements LiveRepository {
  WidgetLiveRepository(this.loader);
  final Future<List<LiveRoom>> Function() loader;

  @override
  Future<List<LiveRoom>> getLiveRooms() => loader();

  @override
  Future<LiveRoom> getLiveRoomDetail(String roomId) async => testRoom;

  @override
  Future<LiveRoom> createLiveRoom({
    required String title,
    required String anchorName,
    required String category,
  }) async => testRoom;

  @override
  Future<LiveRoom> startLiveRoom(String roomId) async => testRoom;

  @override
  Future<LiveRoom> stopLiveRoom(String roomId) async => testRoom;

  @override
  Future<LiveInteraction> toggleFollow(String roomId) async =>
      const LiveInteraction(active: true, count: 1);

  @override
  Future<LiveInteraction> toggleLike(String roomId) async =>
      const LiveInteraction(active: true, count: 1);
}

const testRoom = LiveRoom(
  id: 1,
  title: '深夜音乐陪伴',
  anchorName: '',
  anchorAvatar: '',
  onlineCount: 10000,
  coverUrl: '',
  status: 'living',
  playUrl: '',
  pushUrl: '',
  streamName: '',
  category: '音乐',
);

void main() {
  testWidgets(
    'LiveRoomCard renders placeholder, large count, and invokes tap',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.data(AppThemeId.starryPurple),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 360,
              child: LiveRoomCard(room: testRoom, onTap: () => tapped = true),
            ),
          ),
        ),
      );

      expect(find.text('直播中'), findsOneWidget);
      expect(find.text('1.0万'), findsOneWidget);
      expect(find.text('匿名主播'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-room-1')));
      expect(tapped, isTrue);
    },
  );

  testWidgets('HomePage displays empty state and network error with retry', (
    tester,
  ) async {
    var shouldFail = false;
    final repository = WidgetLiveRepository(() async {
      if (shouldFail) throw StateError('网络失败');
      return const <LiveRoom>[];
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [liveRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.data(AppThemeId.starryPurple),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有正在直播的房间'), findsOneWidget);

    shouldFail = true;
    final failingRepository = WidgetLiveRepository(() async {
      throw StateError('网络失败');
    });
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          liveRepositoryProvider.overrideWithValue(failingRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.data(AppThemeId.starryPurple),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('直播列表加载失败'), findsOneWidget);
    expect(find.textContaining('网络失败'), findsOneWidget);

    final retryRepository = WidgetLiveRepository(() async => const []);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [liveRepositoryProvider.overrideWithValue(retryRepository)],
        child: MaterialApp(
          theme: AppTheme.data(AppThemeId.starryPurple),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时没有正在直播的房间'), findsOneWidget);
  });
}
