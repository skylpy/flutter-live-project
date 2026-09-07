import '../../../../core/network/api_client.dart';
import '../models/search_result.dart';

class SearchRemoteDataSource {
  const SearchRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<SearchResult> search(String query) async {
    final response = await _apiClient.get<SearchResult>(
      '/search?q=${Uri.encodeQueryComponent(query)}',
      parseData: SearchResult.fromJson,
    );
    return response.data;
  }
}
