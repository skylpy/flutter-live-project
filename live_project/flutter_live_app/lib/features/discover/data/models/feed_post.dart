/// 动态广场的展示模型。
///
/// 页面只依赖这个数据契约，不直接读取后端 JSON，也不关心数据来自缓存还是网络。
class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.author,
    required this.body,
    required this.timeLabel,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.liked,
    required this.mediaKind,
  });

  final int id;
  final int authorId;
  final String author;
  final String body;
  final String timeLabel;
  final int likes;
  final int comments;
  final int shares;
  final bool liked;
  final FeedMediaKind mediaKind;

  factory FeedPost.fromJson(Map<String, Object?> json) {
    return FeedPost(
      id: _asInt(json['id']),
      authorId: _asInt(json['authorId'] ?? json['author_id']),
      author: _asString(json['author']),
      body: _asString(json['body']),
      timeLabel: _asString(json['timeLabel'] ?? json['time_label']),
      likes: _asInt(json['likes']),
      comments: _asInt(json['comments']),
      shares: _asInt(json['shares']),
      liked: json['liked'] == true,
      mediaKind: FeedMediaKind.values.firstWhere(
        (kind) =>
            kind.name == _asString(json['mediaKind'] ?? json['media_kind']),
        orElse: () => FeedMediaKind.none,
      ),
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _asString(Object? value) => value is String ? value : '';

  FeedPost copyWith({bool? liked, int? likes}) {
    return FeedPost(
      id: id,
      authorId: authorId,
      author: author,
      body: body,
      timeLabel: timeLabel,
      likes: likes ?? this.likes,
      comments: comments,
      shares: shares,
      liked: liked ?? this.liked,
      mediaKind: mediaKind,
    );
  }
}

enum FeedMediaKind { portrait, landscape, none }

class FeedInteraction {
  const FeedInteraction({required this.active, required this.count});

  final bool active;
  final int count;

  factory FeedInteraction.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return FeedInteraction(
      active: json['active'] == true,
      count: json['count'] is int
          ? json['count']! as int
          : int.tryParse('${json['count']}') ?? 0,
    );
  }
}
