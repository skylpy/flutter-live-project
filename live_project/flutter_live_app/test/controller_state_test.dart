import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_live_app/core/network/api_provider.dart';
import 'package:flutter_live_app/features/auth/data/models/auth_session.dart';
import 'package:flutter_live_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter_live_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_live_app/features/discover/data/models/feed_post.dart';
import 'package:flutter_live_app/features/discover/data/repositories/feed_repository.dart';
import 'package:flutter_live_app/features/discover/presentation/controllers/feed_controller.dart';
import 'package:flutter_live_app/features/live/data/models/live_interaction.dart';
import 'package:flutter_live_app/features/live/data/models/live_room.dart';
import 'package:flutter_live_app/features/live/domain/repositories/live_repository.dart';
import 'package:flutter_live_app/features/live/presentation/controllers/live_list_controller.dart';

class FakeAuthRepository implements AuthRepository {
  final AuthSession session = const AuthSession(
    accessToken: 'token-1',
    tokenType: 'bearer',
    user: AuthUser(id: 1, username: 'kevin', displayName: 'Kevin'),
  );
  bool failLogin = false;

  @override
  Future<AuthSession> login(String username, String password) async {
    if (failLogin) throw StateError('network failed');
    return session;
  }

  @override
  Future<AuthSession> register(
    String username,
    String password,
    String displayName,
  ) async => session;

  @override
  Future<AuthUser> getCurrentUser() async => session.user;
}

class FakeLiveRepository implements LiveRepository {
  FakeLiveRepository(this.rooms);
  List<LiveRoom> rooms;
  bool fail = false;
  int loadCalls = 0;

  @override
  Future<List<LiveRoom>> getLiveRooms() async {
    loadCalls++;
    await Future<void>.delayed(Duration.zero);
    if (fail) throw StateError('network timeout');
    return rooms;
  }

  @override
  Future<LiveRoom> getLiveRoomDetail(String roomId) async => rooms.first;

  @override
  Future<LiveRoom> createLiveRoom({
    required String title,
    required String anchorName,
    required String category,
  }) async => rooms.first;

  @override
  Future<LiveRoom> startLiveRoom(String roomId) async => rooms.first;

  @override
  Future<LiveRoom> stopLiveRoom(String roomId) async => rooms.first;

  @override
  Future<LiveInteraction> toggleFollow(String roomId) async =>
      const LiveInteraction(active: true, count: 1);

  @override
  Future<LiveInteraction> toggleLike(String roomId) async =>
      const LiveInteraction(active: true, count: 1);
}

class FakeFeedRepository implements FeedRepository {
  FakeFeedRepository(this.posts);
  List<FeedPost> posts;
  bool fail = false;
  int toggleCalls = 0;

  @override
  Future<List<FeedPost>> getPosts(String tab) async {
    if (fail) throw StateError('feed unavailable');
    return posts;
  }

  @override
  Future<FeedInteraction> toggleLike(int postId) async {
    toggleCalls++;
    return const FeedInteraction(active: true, count: 9);
  }

  @override
  Future<void> deletePost(int postId) async {}

  @override
  Future<FeedPost> getPost(int postId) async => posts.first;

  @override
  Future<List<FeedComment>> getComments(int postId) async => const [];

  @override
  Future<FeedComment> createComment({
    required int postId,
    required String body,
    int? parentId,
  }) async => const FeedComment(
    id: 1,
    authorId: 1,
    author: 'Kevin',
    body: '评论',
    timeLabel: '刚刚',
  );

  @override
  Future<FeedAuthorProfile> getAuthorProfile(int userId) async =>
      const FeedAuthorProfile(
        id: 1,
        username: 'kevin',
        displayName: 'Kevin',
        followingCount: 0,
        followerCount: 0,
        postCount: 0,
        following: false,
        isSelf: true,
        posts: [],
      );

  @override
  Future<FeedInteraction> toggleUserFollow(int userId) async =>
      const FeedInteraction(active: true, count: 1);

  @override
  Future<FeedPost> createPost({
    required String body,
    required List<int> fileIds,
  }) async => posts.first;
}

LiveRoom room() => const LiveRoom(
  id: 1,
  title: '测试直播',
  anchorName: '主播',
  anchorAvatar: '',
  onlineCount: 0,
  coverUrl: '',
  status: 'living',
  playUrl: 'https://example.invalid/live.m3u8',
  pushUrl: '',
  streamName: '',
  category: '推荐',
);

FeedPost post() => const FeedPost(
  id: 1,
  authorId: 1,
  author: 'Kevin',
  body: '正文',
  timeLabel: '刚刚',
  likes: 2,
  comments: 0,
  shares: 0,
  liked: false,
  mediaKind: FeedMediaKind.none,
);

void main() {
  test(
    'AuthController saves token, exposes session, handles failure and logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      expect(await container.read(authControllerProvider.future), isNull);
      await container
          .read(authControllerProvider.notifier)
          .login('kevin', 'secret');
      expect(
        container.read(authControllerProvider).value?.user.username,
        'kevin',
      );
      expect(await container.read(tokenStorageProvider).readToken(), 'token-1');

      repository.failLogin = true;
      await container
          .read(authControllerProvider.notifier)
          .login('kevin', 'bad');
      expect(
        container.read(authControllerProvider),
        isA<AsyncError<AuthSession?>>(),
      );

      await container.read(authControllerProvider.notifier).logout();
      expect(container.read(authControllerProvider).value, isNull);
      expect(await container.read(tokenStorageProvider).readToken(), isNull);
    },
  );

  test(
    'LiveListController returns empty data and transitions to error on refresh',
    () async {
      final repository = FakeLiveRepository([]);
      final container = ProviderContainer(
        overrides: [liveRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      expect(await container.read(liveListControllerProvider.future), isEmpty);
      repository.fail = true;
      await container.read(liveListControllerProvider.notifier).refreshRooms();
      expect(
        container.read(liveListControllerProvider),
        isA<AsyncError<List<LiveRoom>>>(),
      );
    },
  );

  test(
    'LiveListController keeps a coherent result across concurrent refreshes',
    () async {
      final repository = FakeLiveRepository([room()]);
      final container = ProviderContainer(
        overrides: [liveRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(liveListControllerProvider.future);
      final initialCalls = repository.loadCalls;
      await Future.wait([
        container.read(liveListControllerProvider.notifier).refreshRooms(),
        container.read(liveListControllerProvider.notifier).refreshRooms(),
      ]);

      expect(repository.loadCalls, initialCalls + 2);
      expect(
        container.read(liveListControllerProvider).requireValue.single.id,
        1,
      );
    },
  );

  test('FeedController updates only the target post after a like', () async {
    final repository = FakeFeedRepository([post()]);
    final container = ProviderContainer(
      overrides: [feedRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(feedControllerProvider.future);
    await container.read(feedControllerProvider.notifier).toggleLike(1);
    final state = container.read(feedControllerProvider).requireValue;
    expect(state.single.liked, isTrue);
    expect(state.single.likes, 9);
    expect(repository.toggleCalls, 1);
  });
}
