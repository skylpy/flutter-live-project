class LiveChatMessage {
  const LiveChatMessage({
    required this.type,
    required this.message,
    required this.userName,
    this.event,
    this.onlineCount,
  });

  final String type;
  final String message;
  final String userName;
  final String? event;
  final int? onlineCount;

  factory LiveChatMessage.fromJson(Map<String, Object?> json) {
    final rawCount = json['onlineCount'];
    return LiveChatMessage(
      type: json['type'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      event: json['event'] as String?,
      onlineCount: rawCount is int ? rawCount : int.tryParse('$rawCount'),
    );
  }
}
