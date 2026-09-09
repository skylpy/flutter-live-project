import '../datasources/message_remote_data_source.dart';
import '../models/direct_message.dart';
import '../models/message_conversation.dart';
import 'message_repository.dart';

class MessageRepositoryImpl implements MessageRepository {
  const MessageRepositoryImpl(this._dataSource);

  final MessageRemoteDataSource _dataSource;

  @override
  Future<List<MessageConversation>> getConversations() =>
      _dataSource.getConversations();

  @override
  Future<void> markConversationRead(int userId) =>
      _dataSource.markConversationRead(userId);

  @override
  Future<List<DirectMessage>> getConversation(int userId) =>
      _dataSource.getConversation(userId);

  @override
  Future<DirectMessage> sendMessage({
    required int recipientId,
    required String body,
    required List<int> fileIds,
  }) => _dataSource.sendMessage(
    recipientId: recipientId,
    body: body,
    fileIds: fileIds,
  );
}
