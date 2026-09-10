import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_live_app/features/live/data/models/live_chat_message.dart';
import 'package:flutter_live_app/features/wallet/data/models/wallet_models.dart';

void main() {
  test('wallet and gift contracts parse backend camelCase payloads', () {
    final wallet = WalletSummary.fromJson(<String, Object?>{
      'availableBalance': 868,
      'incomeBalance': 132,
      'currencyName': '金币',
      'incomeName': '礼物收益',
      'testMode': true,
    });
    final receipt = GiftTransactionReceipt.fromJson(<String, Object?>{
      'id': 9,
      'roomId': 3,
      'senderId': 1,
      'senderName': '观众',
      'anchorId': 2,
      'anchorName': '主播',
      'giftId': 2,
      'giftName': '玫瑰',
      'giftIcon': '🌹',
      'animationKey': 'rose',
      'quantity': 2,
      'totalAmount': 132,
      'senderBalance': 868,
      'anchorIncome': 132,
      'replayed': false,
    });

    expect(wallet.availableBalance, 868);
    expect(wallet.testMode, isTrue);
    expect(receipt.giftName, '玫瑰');
    expect(receipt.senderBalance, 868);
  });

  test('live WebSocket gift event parses the confirmed receipt payload', () {
    final message = LiveChatMessage.fromJson(<String, Object?>{
      'type': 'gift',
      'event': 'sent',
      'userName': '观众',
      'message': '观众 送出了 玫瑰 × 1',
      'gift': <String, Object?>{
        'id': 9,
        'senderName': '观众',
        'giftName': '玫瑰',
        'giftIcon': '🌹',
        'animationKey': 'rose',
        'quantity': 1,
        'totalAmount': 66,
        'anchorIncome': 66,
      },
    });

    expect(message.type, 'gift');
    expect(message.gift?.giftName, '玫瑰');
    expect(message.gift?.quantity, 1);
  });
}
