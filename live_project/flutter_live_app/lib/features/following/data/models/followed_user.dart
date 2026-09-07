class FollowedUser {
  const FollowedUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final int id;
  final String username;
  final String displayName;

  factory FollowedUser.fromJson(Map<String, Object?> json) => FollowedUser(
    id: json['id'] is int
        ? json['id']! as int
        : int.tryParse('${json['id']}') ?? 0,
    username: json['username'] is String ? json['username']! as String : '',
    displayName: json['displayName'] is String
        ? json['displayName']! as String
        : (json['display_name'] is String
              ? json['display_name']! as String
              : ''),
  );
}
