import '../../../../core/network/api_client.dart';
import '../models/message_conversation.dart';

/// 消息中心 HTTP 数据源。
class MessageRemoteDataSource {
  const MessageRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<MessageConversation>> getConversations() async {
    final response = await _apiClient.get<List<MessageConversation>>(
      '/messages/conversations',
      parseData: (value) {
        final items = value is List ? value : const <Object?>[];
        return items
            .whereType<Map>()
            .map(
              (item) =>
                  MessageConversation.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false);
      },
    );
    return response.data;
  }
}
