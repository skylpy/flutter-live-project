import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live_app/features/message/data/models/direct_message.dart';

void main() {
  test(
    'DirectMessage parses a private media message returned by the server',
    () {
      final message = DirectMessage.fromJson({
        'id': 42,
        'senderId': 7,
        'recipientId': 8,
        'body': '看看这个视频',
        'isMine': false,
        'timeLabel': '刚刚',
        'media': [
          {
            'fileId': 11,
            'mediaType': 'video',
            'url': 'https://oss.example.invalid/private/video.mp4',
          },
        ],
      });

      expect(message.senderId, 7);
      expect(message.isMine, isFalse);
      expect(message.media.single.fileId, 11);
      expect(message.media.single.isVideo, isTrue);
    },
  );
}
