import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/message_remote_data_source.dart';
import '../../data/models/message_conversation.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/message_repository_impl.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepositoryImpl(
    MessageRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final messageControllerProvider =
    AsyncNotifierProvider<MessageController, List<MessageConversation>>(
      MessageController.new,
    );

/// 消息页只观察这个 Controller，不直接维护“已读/未读”的临时列表。
class MessageController extends AsyncNotifier<List<MessageConversation>> {
  @override
  Future<List<MessageConversation>> build() =>
      ref.read(messageRepositoryProvider).getConversations();

  Future<void> markRead(int userId) async {
    final current = state.asData?.value;
    if (current == null) return;
    await ref.read(messageRepositoryProvider).markConversationRead(userId);
    state = AsyncData([
      for (final item in current)
        item.userId == userId ? item.markRead() : item,
    ]);
  }
}
