import '../models/direct_message.dart';
import '../models/message_conversation.dart';

abstract interface class MessageRepository {
  Future<List<MessageConversation>> getConversations();

  Future<void> markConversationRead(int userId);

  Future<List<DirectMessage>> getConversation(int userId);

  Future<DirectMessage> sendMessage({
    required int recipientId,
    required String body,
    required List<int> fileIds,
  });
}
