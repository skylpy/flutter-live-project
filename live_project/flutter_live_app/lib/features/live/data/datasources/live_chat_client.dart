import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/environment.dart';
import '../models/live_chat_message.dart';

class LiveChatClient {
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  final _messagesController = StreamController<LiveChatMessage>.broadcast();

  Stream<LiveChatMessage> get messages => _messagesController.stream;

  Future<void> connect(String roomId, String token) async {
    final uri = Uri.parse(
      '${Environment.websocketBaseUrl}/live/ws/rooms/$roomId',
    ).replace(queryParameters: <String, String>{'token': token});
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen((event) {
      if (event is! String) return;
      final json = jsonDecode(event);
      if (json is Map) {
        _messagesController.add(
          LiveChatMessage.fromJson(Map<String, Object?>.from(json)),
        );
      }
    }, onError: _messagesController.addError);
  }

  void sendMessage(String message) {
    _channel?.sink.add(
      jsonEncode(<String, String>{'type': 'chat', 'message': message}),
    );
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messagesController.close();
  }
}
