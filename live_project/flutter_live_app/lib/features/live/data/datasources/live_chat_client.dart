import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
  Timer? _reconnectTimer;
  final _messagesController = StreamController<LiveChatMessage>.broadcast();
  final _stateController =
      StreamController<LiveChatConnectionState>.broadcast();

  String? _roomId;
  String? _token;
  bool _manualDisconnect = true;
  bool _connecting = false;
  bool _disposed = false;
  bool _historyLoaded = false;
  int _reconnectAttempt = 0;
  LiveChatConnectionState _state = LiveChatConnectionState.disconnected;

  Stream<LiveChatMessage> get messages => _messagesController.stream;

  Stream<LiveChatConnectionState> get states => _stateController.stream;

  LiveChatConnectionState get state => _state;

  Future<void> connect(String roomId, String token) async {
    if (_roomId != roomId) _historyLoaded = false;
    _roomId = roomId;
    _token = token;
    _manualDisconnect = false;
    _reconnectAttempt = 0;
    await _loadHistoryIfNeeded(roomId, token);
    await _connectOnce();
  }

  Future<void> _loadHistoryIfNeeded(String roomId, String token) async {
    if (_historyLoaded || _disposed) return;
    _historyLoaded = true;
    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: Environment.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          headers: <String, Object>{'Authorization': 'Bearer $token'},
        ),
      ).get<Object?>('/live/rooms/$roomId/chat/messages');
      final envelope = response.data;
      if (envelope is! Map || envelope['data'] is! List) return;
      for (final raw in envelope['data'] as List) {
        if (_disposed) return;
        if (raw is! Map) continue;
        final payload = Map<String, Object?>.from(raw)..['type'] = 'chat';
        _messagesController.add(LiveChatMessage.fromJson(payload));
      }
    } on DioException {
      // 历史请求不应该阻塞实时连接；网络恢复后 WebSocket 仍可正常收新弹幕。
    }
  }

  void sendMessage(String message) {
    // 统一发送 type=chat 的协议消息，服务端据此区分弹幕和其他事件。
    _channel?.sink.add(
      jsonEncode(<String, String>{'type': 'chat', 'message': message}),
    );
  }

  Future<void> disconnect() async {
    // 离开直播间时取消监听并关闭 socket，避免后台回调和资源泄漏。
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _setState(LiveChatConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _messagesController.close();
    await _stateController.close();
  }

  Future<void> _connectOnce() async {
    if (_disposed || _manualDisconnect || _connecting) return;
    final roomId = _roomId;
    final token = _token;
    if (roomId == null || token == null || token.isEmpty) return;

    _connecting = true;
    _setState(
      _reconnectAttempt == 0
          ? LiveChatConnectionState.connecting
          : LiveChatConnectionState.reconnecting,
    );
    try {
      // Token 放在查询参数中是当前后端 WebSocket 接口的约定。
      final uri = Uri.parse(
        '${Environment.websocketBaseUrl}/live/ws/rooms/$roomId',
      ).replace(queryParameters: <String, String>{'token': token});
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_manualDisconnect || _disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      _setState(LiveChatConnectionState.connected);
      _subscription = channel.stream.listen(
        _handleData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _handleDisconnect();
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  void _handleData(Object? event) {
    // 先过滤非文本帧，再把 JSON 转成类型明确的消息模型。
    if (event is! String) return;
    try {
      final json = jsonDecode(event);
      if (json is Map) {
        _messagesController.add(
          LiveChatMessage.fromJson(Map<String, Object?>.from(json)),
        );
      }
    } on FormatException {
      _messagesController.add(
        const LiveChatMessage(type: 'error', message: '弹幕消息格式错误', userName: ''),
      );
    }
  }

  void _handleDisconnect() {
    if (_manualDisconnect || _disposed) return;
    _subscription = null;
    _channel = null;
    _setState(LiveChatConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null || _manualDisconnect || _disposed) return;
    final seconds = 1 << (_reconnectAttempt.clamp(0, 4));
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_connectOnce().catchError((_) {}));
    });
  }

  void _setState(LiveChatConnectionState next) {
    if (_state == next || _disposed) return;
    _state = next;
    _stateController.add(next);
  }
}

enum LiveChatConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}
