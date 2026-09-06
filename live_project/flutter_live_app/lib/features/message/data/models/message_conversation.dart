/// 消息中心的一行会话摘要。
class MessageConversation {
  const MessageConversation({
    required this.userId,
    required this.userName,
    required this.preview,
    required this.timeLabel,
    required this.unread,
  });

  final int userId;
  final String userName;
  final String preview;
  final String timeLabel;
  final int unread;

  factory MessageConversation.fromJson(Map<String, Object?> json) {
    return MessageConversation(
      userId: _asInt(json['userId'] ?? json['user_id']),
      userName: _asString(json['userName'] ?? json['user_name']),
      preview: _asString(json['preview']),
      timeLabel: _asString(json['timeLabel'] ?? json['time_label']),
      unread: _asInt(json['unread']),
    );
  }

  MessageConversation markRead() => MessageConversation(
    userId: userId,
    userName: userName,
    preview: preview,
    timeLabel: timeLabel,
    unread: 0,
  );

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _asString(Object? value) => value is String ? value : '';
}
