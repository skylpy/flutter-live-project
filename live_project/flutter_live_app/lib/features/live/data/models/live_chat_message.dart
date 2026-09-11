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
    this.isVirtual = false,
    this.virtualRole,
    this.aiGenerated = false,
    this.gift,
  });

  final String type;
  final String message;
  final String userName;
  final String? event;
  final int? onlineCount;

  /// 虚拟居民的身份由服务端签发，客户端不接受发送端伪造该字段。
  final bool isVirtual;
  final String? virtualRole;
  final bool aiGenerated;
  final LiveGiftEvent? gift;

  factory LiveChatMessage.fromJson(Map<String, Object?> json) {
    final rawCount = json['onlineCount'];
    final rawGift = json['gift'];
    return LiveChatMessage(
      type: json['type'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      event: json['event'] as String?,
      onlineCount: rawCount is int ? rawCount : int.tryParse('$rawCount'),
      isVirtual: json['isVirtual'] == true || json['is_virtual'] == true,
      virtualRole:
          json['virtualRole'] as String? ?? json['virtual_role'] as String?,
      aiGenerated: json['aiGenerated'] == true || json['ai_generated'] == true,
      gift: rawGift is Map
          ? LiveGiftEvent.fromJson(Map<String, Object?>.from(rawGift))
          : null,
    );
  }
}

/// 直播房间 WebSocket 中的礼物事件。与 REST 送礼回执字段保持一致，
/// 这样主播和观众可基于同一个数据绘制动画而无需额外请求详情。
class LiveGiftEvent {
  const LiveGiftEvent({
    required this.id,
    required this.senderName,
    required this.giftName,
    required this.giftIcon,
    required this.animationKey,
    required this.quantity,
    required this.totalAmount,
    required this.anchorIncome,
  });

  final int id;
  final String senderName;
  final String giftName;
  final String giftIcon;
  final String animationKey;
  final int quantity;
  final int totalAmount;
  final int anchorIncome;

  factory LiveGiftEvent.fromJson(Map<String, Object?> json) => LiveGiftEvent(
    id: _int(json['id']),
    senderName: _text(json['senderName'] ?? json['sender_name']),
    giftName: _text(json['giftName'] ?? json['gift_name']),
    giftIcon: _text(json['giftIcon'] ?? json['gift_icon']),
    animationKey: _text(json['animationKey'] ?? json['animation_key']),
    quantity: _int(json['quantity']),
    totalAmount: _int(json['totalAmount'] ?? json['total_amount']),
    anchorIncome: _int(json['anchorIncome'] ?? json['anchor_income']),
  );
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

String _text(Object? value) => value is String ? value : '';
