/// 钱包与直播礼物的客户端模型。
///
/// 金额统一使用整数金币，不在客户端使用 double，避免展示与服务端账务不一致。
class WalletSummary {
  const WalletSummary({
    required this.availableBalance,
    required this.incomeBalance,
    required this.currencyName,
    required this.incomeName,
    required this.testMode,
  });

  final int availableBalance;
  final int incomeBalance;
  final String currencyName;
  final String incomeName;
  final bool testMode;

  factory WalletSummary.fromJson(Map<String, Object?> json) => WalletSummary(
    availableBalance: _int(
      json['availableBalance'] ?? json['available_balance'],
    ),
    incomeBalance: _int(json['incomeBalance'] ?? json['income_balance']),
    currencyName: _text(json['currencyName'] ?? json['currency_name'], '金币'),
    incomeName: _text(json['incomeName'] ?? json['income_name'], '礼物收益'),
    testMode: json['testMode'] == true || json['test_mode'] == true,
  );
}

class WalletLedgerItem {
  const WalletLedgerItem({
    required this.id,
    required this.balanceType,
    required this.amount,
    required this.balanceAfter,
    required this.businessType,
    required this.title,
    required this.timeLabel,
  });

  final int id;
  final String balanceType;
  final int amount;
  final int balanceAfter;
  final String businessType;
  final String title;
  final String timeLabel;

  factory WalletLedgerItem.fromJson(Map<String, Object?> json) =>
      WalletLedgerItem(
        id: _int(json['id']),
        balanceType: _text(json['balanceType'] ?? json['balance_type']),
        amount: _int(json['amount']),
        balanceAfter: _int(json['balanceAfter'] ?? json['balance_after']),
        businessType: _text(json['businessType'] ?? json['business_type']),
        title: _text(json['title'], '钱包变动'),
        timeLabel: _text(json['timeLabel'] ?? json['time_label']),
      );
}

class GiftCatalogItem {
  const GiftCatalogItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.animationKey,
    required this.price,
  });

  final int id;
  final String name;
  final String icon;
  final String animationKey;
  final int price;

  factory GiftCatalogItem.fromJson(Map<String, Object?> json) =>
      GiftCatalogItem(
        id: _int(json['id']),
        name: _text(json['name']),
        icon: _text(json['icon']),
        animationKey: _text(json['animationKey'] ?? json['animation_key']),
        price: _int(json['price']),
      );
}

class GiftTransactionReceipt {
  const GiftTransactionReceipt({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.anchorId,
    required this.anchorName,
    required this.giftId,
    required this.giftName,
    required this.giftIcon,
    required this.animationKey,
    required this.quantity,
    required this.totalAmount,
    required this.senderBalance,
    required this.anchorIncome,
    required this.replayed,
  });

  final int id;
  final int roomId;
  final int senderId;
  final String senderName;
  final int anchorId;
  final String anchorName;
  final int giftId;
  final String giftName;
  final String giftIcon;
  final String animationKey;
  final int quantity;
  final int totalAmount;
  final int senderBalance;
  final int anchorIncome;
  final bool replayed;

  factory GiftTransactionReceipt.fromJson(Map<String, Object?> json) =>
      GiftTransactionReceipt(
        id: _int(json['id']),
        roomId: _int(json['roomId'] ?? json['room_id']),
        senderId: _int(json['senderId'] ?? json['sender_id']),
        senderName: _text(json['senderName'] ?? json['sender_name']),
        anchorId: _int(json['anchorId'] ?? json['anchor_id']),
        anchorName: _text(json['anchorName'] ?? json['anchor_name']),
        giftId: _int(json['giftId'] ?? json['gift_id']),
        giftName: _text(json['giftName'] ?? json['gift_name']),
        giftIcon: _text(json['giftIcon'] ?? json['gift_icon']),
        animationKey: _text(json['animationKey'] ?? json['animation_key']),
        quantity: _int(json['quantity']),
        totalAmount: _int(json['totalAmount'] ?? json['total_amount']),
        senderBalance: _int(json['senderBalance'] ?? json['sender_balance']),
        anchorIncome: _int(json['anchorIncome'] ?? json['anchor_income']),
        replayed: json['replayed'] == true,
      );
}

class RoomGiftStats {
  const RoomGiftStats({
    required this.roomId,
    required this.anchorId,
    required this.totalRevenue,
    required this.totalGiftCount,
    required this.topSupporters,
  });

  final int roomId;
  final int anchorId;
  final int totalRevenue;
  final int totalGiftCount;
  final List<GiftRankItem> topSupporters;

  factory RoomGiftStats.fromJson(Map<String, Object?> json) {
    final rawRanks = json['topSupporters'] ?? json['top_supporters'];
    return RoomGiftStats(
      roomId: _int(json['roomId'] ?? json['room_id']),
      anchorId: _int(json['anchorId'] ?? json['anchor_id']),
      totalRevenue: _int(json['totalRevenue'] ?? json['total_revenue']),
      totalGiftCount: _int(json['totalGiftCount'] ?? json['total_gift_count']),
      topSupporters: rawRanks is List
          ? rawRanks
                .whereType<Map>()
                .map(
                  (item) =>
                      GiftRankItem.fromJson(Map<String, Object?>.from(item)),
                )
                .toList(growable: false)
          : const <GiftRankItem>[],
    );
  }
}

class GiftRankItem {
  const GiftRankItem({
    required this.userId,
    required this.userName,
    required this.totalAmount,
    required this.giftCount,
  });

  final int userId;
  final String userName;
  final int totalAmount;
  final int giftCount;

  factory GiftRankItem.fromJson(Map<String, Object?> json) => GiftRankItem(
    userId: _int(json['userId'] ?? json['user_id']),
    userName: _text(json['userName'] ?? json['user_name']),
    totalAmount: _int(json['totalAmount'] ?? json['total_amount']),
    giftCount: _int(json['giftCount'] ?? json['gift_count']),
  );
}

class GiftRecordItem {
  const GiftRecordItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.giftName,
    required this.giftIcon,
    required this.quantity,
    required this.totalAmount,
    required this.timeLabel,
  });

  final int id;
  final int senderId;
  final String senderName;
  final String giftName;
  final String giftIcon;
  final int quantity;
  final int totalAmount;
  final String timeLabel;

  factory GiftRecordItem.fromJson(Map<String, Object?> json) => GiftRecordItem(
    id: _int(json['id']),
    senderId: _int(json['senderId'] ?? json['sender_id']),
    senderName: _text(json['senderName'] ?? json['sender_name']),
    giftName: _text(json['giftName'] ?? json['gift_name']),
    giftIcon: _text(json['giftIcon'] ?? json['gift_icon']),
    quantity: _int(json['quantity']),
    totalAmount: _int(json['totalAmount'] ?? json['total_amount']),
    timeLabel: _text(json['timeLabel'] ?? json['time_label']),
  );
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

String _text(Object? value, [String fallback = '']) =>
    value is String && value.isNotEmpty ? value : fallback;
