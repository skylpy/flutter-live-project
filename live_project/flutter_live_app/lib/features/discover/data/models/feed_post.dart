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
    this.media = const [],
    this.commentsPreview = const [],
    this.canDelete = false,
    this.isVirtual = false,
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
  final List<FeedMedia> media;
  final List<FeedComment> commentsPreview;
  final bool canDelete;
  final bool isVirtual;

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
      media: (json['media'] is List ? json['media'] as List : const <Object?>[])
          .whereType<Map>()
          .map((item) => FeedMedia.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
      commentsPreview:
          (json['commentsPreview'] ?? json['comments_preview']) is List
          ? ((json['commentsPreview'] ?? json['comments_preview']) as List)
                .whereType<Map>()
                .map(
                  (item) =>
                      FeedComment.fromJson(Map<String, Object?>.from(item)),
                )
                .toList(growable: false)
          : const [],
      canDelete: json['canDelete'] == true || json['can_delete'] == true,
      isVirtual: json['isVirtual'] == true || json['is_virtual'] == true,
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _asString(Object? value) => value is String ? value : '';

  FeedPost copyWith({
    bool? liked,
    int? likes,
    int? comments,
    List<FeedComment>? commentsPreview,
    bool? isVirtual,
  }) {
    return FeedPost(
      id: id,
      authorId: authorId,
      author: author,
      body: body,
      timeLabel: timeLabel,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares,
      liked: liked ?? this.liked,
      mediaKind: mediaKind,
      media: media,
      commentsPreview: commentsPreview ?? this.commentsPreview,
      canDelete: canDelete,
      isVirtual: isVirtual ?? this.isVirtual,
    );
  }
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.authorId,
    required this.author,
    required this.body,
    required this.timeLabel,
    this.parentId,
    this.replyToAuthor,
    this.isVirtual = false,
  });

  final int id;
  final int authorId;
  final String author;
  final String body;
  final String timeLabel;
  final int? parentId;
  final String? replyToAuthor;
  final bool isVirtual;

  factory FeedComment.fromJson(Map<String, Object?> json) => FeedComment(
    id: FeedPost._asInt(json['id']),
    authorId: FeedPost._asInt(json['authorId'] ?? json['author_id']),
    author: FeedPost._asString(json['author']),
    body: FeedPost._asString(json['body']),
    timeLabel: FeedPost._asString(json['timeLabel'] ?? json['time_label']),
    parentId: (json['parentId'] ?? json['parent_id']) == null
        ? null
        : FeedPost._asInt(json['parentId'] ?? json['parent_id']),
    replyToAuthor:
        FeedPost._asString(json['replyToAuthor'] ?? json['reply_to_author'])
            .isEmpty
        ? null
        : FeedPost._asString(json['replyToAuthor'] ?? json['reply_to_author']),
    isVirtual: json['isVirtual'] == true || json['is_virtual'] == true,
  );
}

class FeedAuthorProfile {
  const FeedAuthorProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.followingCount,
    required this.followerCount,
    required this.postCount,
    required this.following,
    required this.isSelf,
    required this.posts,
  });

  final int id;
  final String username;
  final String displayName;
  final int followingCount;
  final int followerCount;
  final int postCount;
  final bool following;
  final bool isSelf;
  final List<FeedPost> posts;

  factory FeedAuthorProfile.fromJson(Map<String, Object?> json) =>
      FeedAuthorProfile(
        id: FeedPost._asInt(json['id']),
        username: FeedPost._asString(json['username']),
        displayName: FeedPost._asString(
          json['displayName'] ?? json['display_name'],
        ),
        followingCount: FeedPost._asInt(
          json['followingCount'] ?? json['following_count'],
        ),
        followerCount: FeedPost._asInt(
          json['followerCount'] ?? json['follower_count'],
        ),
        postCount: FeedPost._asInt(json['postCount'] ?? json['post_count']),
        following: json['following'] == true,
        isSelf: json['isSelf'] == true || json['is_self'] == true,
        posts: (json['posts'] is List ? json['posts'] as List : const [])
            .whereType<Map>()
            .map((post) => FeedPost.fromJson(Map<String, Object?>.from(post)))
            .toList(growable: false),
      );
}

enum FeedMediaKind { portrait, landscape, image, video, none }

class FeedMedia {
  const FeedMedia({
    required this.fileId,
    required this.mediaType,
    required this.url,
  });

  final int fileId;
  final String mediaType;
  final String url;

  bool get isVideo => mediaType == 'video';

  factory FeedMedia.fromJson(Map<String, Object?> json) => FeedMedia(
    fileId: FeedPost._asInt(json['fileId'] ?? json['file_id']),
    mediaType: FeedPost._asString(json['mediaType'] ?? json['media_type']),
    url: FeedPost._asString(json['url']),
  );
}

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
