import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/environment.dart';
import '../models/live_chat_message.dart';

/// 直播间 WebSocket 客户端。
///
/// 当前只处理文本弹幕和在线人数事件，不承载视频流。视频走原生播放器，
/// 这样 IM 断线不会影响播放器，也方便以后分别做重连策略。
class LiveChatClient {
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  final _messagesController = StreamController<LiveChatMessage>.broadcast();

  Stream<LiveChatMessage> get messages => _messagesController.stream;

  Future<void> connect(String roomId, String token) async {
    // Token 放在查询参数中是当前后端 WebSocket 接口的约定。
    final uri = Uri.parse(
      '${Environment.websocketBaseUrl}/live/ws/rooms/$roomId',
    ).replace(queryParameters: <String, String>{'token': token});
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen((event) {
      // 先过滤非文本帧，再把 JSON 转成类型明确的消息模型。
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
    // 统一发送 type=chat 的协议消息，服务端据此区分弹幕和其他事件。
    _channel?.sink.add(
      jsonEncode(<String, String>{'type': 'chat', 'message': message}),
    );
  }

  Future<void> disconnect() async {
    // 离开直播间时取消监听并关闭 socket，避免后台回调和资源泄漏。
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
