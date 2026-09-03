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
  final String category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LiveRoom.fromJson(Map<String, Object?> json) {
    return LiveRoom(
      id: _int(json['id']),
      title: _string(json['title']),
      anchorName: _string(json['anchorName'] ?? json['anchor_name']),
      anchorAvatar: _string(json['anchorAvatar'] ?? json['anchor_avatar']),
      onlineCount: _int(json['onlineCount'] ?? json['online_count']),
      coverUrl: _string(json['coverUrl'] ?? json['cover_url']),
      status: _string(json['status'], fallback: 'living'),
      playUrl: _string(json['playUrl'] ?? json['play_url']),
      category: _string(json['category']),
      createdAt: _date(json['createdAt'] ?? json['created_at']),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'anchorName': anchorName,
      'anchorAvatar': anchorAvatar,
      'onlineCount': onlineCount,
      'coverUrl': coverUrl,
      'status': status,
      'playUrl': playUrl,
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
