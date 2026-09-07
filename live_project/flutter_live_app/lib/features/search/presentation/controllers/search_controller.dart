import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/search_remote_data_source.dart';
import '../../data/models/search_result.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/search_repository_impl.dart';

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepositoryImpl(
    SearchRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, SearchResult?>(
      SearchController.new,
    );

class SearchController extends AsyncNotifier<SearchResult?> {
  @override
  SearchResult? build() => null;

  Future<void> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(searchRepositoryProvider).search(value),
    );
  }
}
