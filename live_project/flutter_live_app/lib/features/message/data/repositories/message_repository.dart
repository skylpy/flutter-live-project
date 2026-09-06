import '../models/message_conversation.dart';

abstract interface class MessageRepository {
  Future<List<MessageConversation>> getConversations();
}
