import '../datasources/search_remote_data_source.dart';
import '../models/search_result.dart';
import 'search_repository.dart';

class SearchRepositoryImpl implements SearchRepository {
  const SearchRepositoryImpl(this._dataSource);

  final SearchRemoteDataSource _dataSource;

  @override
  Future<SearchResult> search(String query) => _dataSource.search(query);
}
