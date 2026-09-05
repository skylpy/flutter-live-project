/// 客户端表示一个直播间的模型。
///
/// fromJson 兼容后端 camelCase 和数据库常见的 snake_case，并为缺失字段提供
/// 安全默认值，避免不完整数据直接导致页面崩溃。
class LiveRoom {
  const LiveRoom({
    required this.id,
    required this.title,
    required this.anchorName,
    required this.anchorAvatar,
    required this.onlineCount,
    required this.coverUrl,
    required this.status,
    required this.playUrl,
    required this.pushUrl,
    required this.streamName,
    required this.category,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String anchorName;
  final String anchorAvatar;
  final int onlineCount;
  final String coverUrl;
  final String status;
  final String playUrl;
  final String pushUrl;
  final String streamName;
  final String category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LiveRoom.fromJson(Map<String, Object?> json) {
    // 所有服务端字段在这里集中转换，页面只使用类型明确的 Dart 字段。
    return LiveRoom(
      id: _int(json['id']),
      title: _string(json['title']),
      anchorName: _string(json['anchorName'] ?? json['anchor_name']),
      anchorAvatar: _string(json['anchorAvatar'] ?? json['anchor_avatar']),
      onlineCount: _int(json['onlineCount'] ?? json['online_count']),
      coverUrl: _string(json['coverUrl'] ?? json['cover_url']),
      status: _string(json['status'], fallback: 'living'),
      playUrl: _string(json['playUrl'] ?? json['play_url']),
      pushUrl: _string(json['pushUrl'] ?? json['push_url']),
      streamName: _string(json['streamName'] ?? json['stream_name']),
      category: _string(json['category']),
      createdAt: _date(json['createdAt'] ?? json['created_at']),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, Object?> toJson() {
    // toJson 方便缓存、日志和后续向其他接口传递房间快照。
    return <String, Object?>{
      'id': id,
      'title': title,
      'anchorName': anchorName,
      'anchorAvatar': anchorAvatar,
      'onlineCount': onlineCount,
      'coverUrl': coverUrl,
      'status': status,
      'playUrl': playUrl,
      'pushUrl': pushUrl,
      'streamName': streamName,
      'category': category,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static String _string(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value as String? ?? '');
}
