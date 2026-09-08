import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/token_storage.dart';
import '../config/environment.dart';

/// 用户级实时通知连接状态。
enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// 服务端推送的一条用户级实时事件。
class RealtimeNotificationEvent {
  const RealtimeNotificationEvent({
    required this.type,
    required this.event,
    this.notification,
  });

  final String type;
  final String event;
  final Map<String, Object?>? notification;

  factory RealtimeNotificationEvent.fromJson(Map<String, Object?> json) {
    final rawNotification = json['notification'];
    return RealtimeNotificationEvent(
      type: json['type'] as String? ?? 'unknown',
      event: json['event'] as String? ?? '',
      notification: rawNotification is Map
          ? Map<String, Object?>.from(rawNotification)
          : null,
    );
  }
}

/// 登录用户的实时通知客户端。
///
/// 历史通知仍由 REST 获取；WebSocket 只负责把新私信、关注、点赞和已读变化
/// 实时送到当前客户端。连接断开后使用有限速指数退避自动重连，退出登录时
/// 由上层显式断开，避免旧用户继续收到事件。
class RealtimeNotificationClient {
  RealtimeNotificationClient(this._tokenStorage);

  final TokenStorage _tokenStorage;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  final _eventsController =
      StreamController<RealtimeNotificationEvent>.broadcast();
  final _stateController =
      StreamController<RealtimeConnectionState>.broadcast();

  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  bool _manualDisconnect = true;
  bool _connecting = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  Stream<RealtimeNotificationEvent> get events => _eventsController.stream;

  Stream<RealtimeConnectionState> get states => _stateController.stream;

  RealtimeConnectionState get state => _state;

  Future<void> connect() async {
    _manualDisconnect = false;
    if (_disposed || _connecting || _channel != null) return;
    final token = await _tokenStorage.readToken();
    if (_disposed || _manualDisconnect || token == null || token.isEmpty) {
      return;
    }

    _connecting = true;
    _setState(
      _reconnectAttempt == 0
          ? RealtimeConnectionState.connecting
          : RealtimeConnectionState.reconnecting,
    );
    try {
      final uri = Uri.parse('${Environment.websocketBaseUrl}/ws/notifications')
          .replace(queryParameters: <String, String>{'token': token});
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_manualDisconnect || _disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      _setState(RealtimeConnectionState.connected);
      _subscription = channel.stream.listen(
        _handleData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _handleDisconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.sink.close();
    _setState(RealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _eventsController.close();
    await _stateController.close();
  }

  void _handleData(Object? rawEvent) {
    if (rawEvent is! String) return;
    try {
      final decoded = jsonDecode(rawEvent);
      if (decoded is Map) {
        _eventsController.add(
          RealtimeNotificationEvent.fromJson(
            Map<String, Object?>.from(decoded),
          ),
        );
      }
    } on FormatException {
      // 一条格式错误的实时事件不能影响后续通知连接。
    }
  }

  void _handleDisconnect() {
    if (_manualDisconnect || _disposed) return;
    _subscription = null;
    _channel = null;
    _setState(RealtimeConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null || _manualDisconnect || _disposed) return;
    final seconds = 1 << (_reconnectAttempt.clamp(0, 4));
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  void _setState(RealtimeConnectionState next) {
    if (_state == next || _disposed) return;
    _state = next;
    _stateController.add(next);
  }
}
