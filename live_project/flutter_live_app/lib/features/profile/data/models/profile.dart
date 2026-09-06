/// 个人中心需要的资料和统计。
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.followingCount,
    required this.followerCount,
    required this.likedCount,
  });

  final int id;
  final String username;
  final String displayName;
  final int followingCount;
  final int followerCount;
  final int likedCount;

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
    id: _asInt(json['id']),
    username: _asString(json['username']),
    displayName: _asString(json['displayName'] ?? json['display_name']),
    followingCount: _asInt(json['followingCount'] ?? json['following_count']),
    followerCount: _asInt(json['followerCount'] ?? json['follower_count']),
    likedCount: _asInt(json['likedCount'] ?? json['liked_count']),
  );

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _asString(Object? value) => value is String ? value : '';
}
