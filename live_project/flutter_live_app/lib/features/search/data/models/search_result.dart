class SearchResult {
  const SearchResult({
    required this.users,
    required this.rooms,
    required this.posts,
  });

  final List<SearchUser> users;
  final List<SearchRoom> rooms;
  final List<SearchPost> posts;

  factory SearchResult.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return SearchResult(
      users: _list(json['users'], SearchUser.fromJson),
      rooms: _list(json['rooms'], SearchRoom.fromJson),
      posts: _list(json['posts'], SearchPost.fromJson),
    );
  }

  static List<T> _list<T>(
    Object? value,
    T Function(Map<String, Object?>) parse,
  ) {
    final items = value is List ? value : const <Object?>[];
    return items
        .whereType<Map>()
        .map((item) => parse(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }
}

class SearchUser {
  const SearchUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final int id;
  final String username;
  final String displayName;

  factory SearchUser.fromJson(Map<String, Object?> json) => SearchUser(
    id: _asInt(json['id']),
    username: _asString(json['username']),
    displayName: _asString(json['displayName'] ?? json['display_name']),
  );
}

class SearchRoom {
  const SearchRoom({
    required this.id,
    required this.title,
    required this.anchorName,
    required this.onlineCount,
    required this.status,
    required this.category,
  });

  final int id;
  final String title;
  final String anchorName;
  final int onlineCount;
  final String status;
  final String category;

  factory SearchRoom.fromJson(Map<String, Object?> json) => SearchRoom(
    id: _asInt(json['id']),
    title: _asString(json['title']),
    anchorName: _asString(json['anchorName'] ?? json['anchor_name']),
    onlineCount: _asInt(json['onlineCount'] ?? json['online_count']),
    status: _asString(json['status']),
    category: _asString(json['category']),
  );
}

class SearchPost {
  const SearchPost({
    required this.id,
    required this.author,
    required this.body,
    required this.timeLabel,
  });

  final int id;
  final String author;
  final String body;
  final String timeLabel;

  factory SearchPost.fromJson(Map<String, Object?> json) => SearchPost(
    id: _asInt(json['id']),
    author: _asString(json['author']),
    body: _asString(json['body']),
    timeLabel: _asString(json['timeLabel'] ?? json['time_label']),
  );
}

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

String _asString(Object? value) => value is String ? value : '';
