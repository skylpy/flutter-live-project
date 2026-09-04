/// 一条 WebSocket 弹幕或在线人数事件。
///
/// 它是实时通道的传输模型，不等同于数据库中的 LiveRoom；两者来源和生命
/// 周期不同，所以分开建模。
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
