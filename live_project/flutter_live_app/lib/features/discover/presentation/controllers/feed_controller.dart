import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/feed_remote_data_source.dart';
import '../../data/models/feed_post.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/repositories/feed_repository_impl.dart';

final feedRemoteDataSourceProvider = Provider<FeedRemoteDataSource>(
  (ref) => FeedRemoteDataSource(ref.watch(apiClientProvider)),
);

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => FeedRepositoryImpl(ref.watch(feedRemoteDataSourceProvider)),
);

final feedControllerProvider =
    AsyncNotifierProvider<FeedController, List<FeedPost>>(FeedController.new);

/// Feed Controller 只负责加载列表和本地乐观点赞，页面不持有业务列表状态。
class FeedController extends AsyncNotifier<List<FeedPost>> {
  String _tab = '推荐';

  @override
  Future<List<FeedPost>> build() =>
      ref.read(feedRepositoryProvider).getPosts(_tab);

  Future<void> selectTab(String tab) async {
    _tab = tab;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(feedRepositoryProvider).getPosts(tab),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(feedRepositoryProvider).getPosts(_tab),
    );
  }

  Future<void> toggleLike(int id) async {
    final current = state.asData?.value;
    if (current == null) return;
    final result = await AsyncValue.guard(
      () => ref.read(feedRepositoryProvider).toggleLike(id),
    );
    result.when(
      data: (interaction) {
        state = AsyncData([
          for (final post in current)
            post.id == id
                ? post.copyWith(
                    liked: interaction.active,
                    likes: interaction.count,
                  )
                : post,
        ]);
      },
      error: (error, stack) => state = AsyncError(error, stack),
      loading: () {},
    );
  }

  Future<void> deletePost(int id) async {
    final current = state.asData?.value;
    if (current == null) return;
    await ref.read(feedRepositoryProvider).deletePost(id);
    state = AsyncData(current.where((post) => post.id != id).toList());
  }
}
